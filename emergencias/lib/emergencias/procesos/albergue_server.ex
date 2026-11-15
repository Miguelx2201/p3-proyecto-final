defmodule Emergencias.Procesos.AlbergueServer do
  @moduledoc """
  Proceso dueño de un albergue. Hay uno por albergue, registrado en
  `Emergencias.Registry` con la llave `{:albergue, id}`.

  Serializa las operaciones de un mismo albergue y deja que albergues distintos
  se atiendan en paralelo. Cada proceso escribe solo sus dos archivos, así
  ningún archivo tiene dos escritores:

    * `albergues/<id>.csv`: una fila con los datos del albergue.
    * `albergues/<id>_personas.csv`: una fila por documento.

  Ambos archivos se reescriben tras cada cambio, primero el de personas y luego
  el del albergue. No es una operación atómica entre los dos archivos.

  Si el cambio no se puede guardar, la respuesta es
  `{:error, {:persistencia, razon}}` y el estado en memoria no cambia.

  Si no hay proceso para el id, las funciones de la API responden
  `{:error, :no_encontrado}`.
  """

  use GenServer

  alias Emergencias.CSV
  alias Emergencias.Dominio.Albergue
  alias Emergencias.Util

  @registro Emergencias.Registry
  @carpeta "albergues"
  @sufijo_personas "_personas"
  @cabecera "id;nombre;zona;capacidad_maxima;ocupacion_actual"
  @cabecera_personas "documento"

  # ---------------------------------------------------------------------------
  # Arranque
  # ---------------------------------------------------------------------------

  @doc """
  Arranca el proceso del albergue, registrado por su id.

  Si ya existe `albergues/<id>.csv`, `init/1` carga ese archivo y descarta el
  albergue recibido (así un reinicio recupera los datos). Si no existe, guarda
  el albergue recibido.
  """
  @spec start_link(Albergue.t()) :: GenServer.on_start() | {:error, :albergue_invalido}
  def start_link(%Albergue{id: id} = albergue) when is_binary(id) do
    GenServer.start_link(__MODULE__, albergue, name: via(id))
  end

  def start_link(_otro), do: {:error, :albergue_invalido}

  # ---------------------------------------------------------------------------
  # API por id
  # ---------------------------------------------------------------------------

  @doc "Estado actual del albergue."
  @spec consultar(term()) :: {:ok, Albergue.t()} | {:error, atom()}
  def consultar(id), do: llamar(id, :consultar)

  @doc "Cupos libres del albergue."
  @spec cupos(term()) :: {:ok, integer()} | {:error, atom()}
  def cupos(id), do: llamar(id, :cupos)

  @doc """
  Registra el ingreso de `documento`. Devuelve los errores de
  `Albergue.registrar_ingreso/2` o `{:error, {:persistencia, razon}}`.
  """
  @spec ingreso(term(), term()) :: {:ok, Albergue.t()} | {:error, term()}
  def ingreso(id, documento), do: llamar(id, {:ingreso, documento})

  @doc """
  Registra la salida de `documento`. Devuelve los errores de
  `Albergue.registrar_salida/2` o `{:error, {:persistencia, razon}}`.
  """
  @spec salida(term(), term()) :: {:ok, Albergue.t()} | {:error, term()}
  def salida(id, documento), do: llamar(id, {:salida, documento})

  @doc "Estado de un proceso concreto (lo usa `AlberguesSupervisor.listar/0`)."
  @spec estado(pid()) :: {:ok, Albergue.t()} | {:error, atom()}
  def estado(pid) when is_pid(pid), do: llamar_pid(pid, :consultar)

  # ---------------------------------------------------------------------------
  # Archivos
  # ---------------------------------------------------------------------------

  @doc """
  Verdadero si el id sirve como nombre de archivo: solo letras, números, `_` y
  `-`, y que no termine en `_personas` (chocaría con el archivo de personas de
  otro albergue).
  """
  @spec id_valido?(term()) :: boolean()
  def id_valido?(id) when is_binary(id) do
    Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id) and not String.ends_with?(id, @sufijo_personas)
  end

  def id_valido?(_otro), do: false

  @doc "Ruta de `albergues/<id>.csv` dentro de la carpeta de datos."
  @spec ruta_albergue(String.t()) :: String.t()
  def ruta_albergue(id), do: CSV.ruta(Path.join(@carpeta, id <> ".csv"))

  @doc "Ruta de `albergues/<id>_personas.csv` dentro de la carpeta de datos."
  @spec ruta_personas(String.t()) :: String.t()
  def ruta_personas(id), do: CSV.ruta(Path.join(@carpeta, id <> @sufijo_personas <> ".csv"))

  @doc """
  Patrón para `Path.wildcard/1` sobre los archivos de `albergues/`.

  La carpeta se normaliza con `Path.expand/1` (separadores `/`, también en
  Windows) y se escapan los caracteres especiales del glob, porque en
  `Path.wildcard/1` la `\\` es el carácter de escape.
  """
  @spec patron_archivos() :: String.t()
  # CORRECCIÓN 1: antes era `CSV.ruta(Path.join(@carpeta, "*.csv"))`, que en
  # Windows dejaba `\` en el patrón y no encontraba ningún archivo.
  def patron_archivos do
    carpeta = @carpeta |> CSV.ruta() |> Path.expand()
    escapada = Regex.replace(~r/[\\?*\[\]{}]/, carpeta, "\\\\\\0")
    escapada <> "/*.csv"
  end

  @doc """
  Id de un albergue a partir de la ruta de su archivo. Devuelve `:error` para los
  archivos `_personas.csv` y para nombres que no son un id válido.
  """
  @spec id_de_archivo(String.t()) :: {:ok, String.t()} | :error
  def id_de_archivo(ruta) do
    id = Path.basename(ruta, ".csv")
    if id_valido?(id), do: {:ok, id}, else: :error
  end

  @doc """
  Lee el albergue guardado en disco (sus dos archivos).

  Errores: `:id_invalido`, `:archivo_invalido` (archivo vacío, línea corrupta o
  id que no coincide con el nombre del archivo) o el error de lectura del
  sistema.
  """
  @spec cargar(term()) :: {:ok, Albergue.t()} | {:error, term()}
  def cargar(id) do
    if id_valido?(id), do: cargar_validado(id), else: {:error, :id_invalido}
  end

  defp cargar_validado(id) do
    # CORRECCIÓN 2: `%Albergue{} = fila` en el patrón para que el compilador
    # sepa el tipo de `fila` al hacer la actualización de la struct.
    with {:ok, [%Albergue{} = fila]} <- CSV.leer(ruta_albergue(id), &albergue_de_linea/1),
         {:ok, documentos} <- CSV.leer(ruta_personas(id), &persona_de_linea/1),
         true <- fila.id == id do
      {:ok, %Albergue{fila | personas: MapSet.new(documentos)}}
    else
      {:ok, _otro} -> {:error, :archivo_invalido}
      false -> {:error, :archivo_invalido}
      {:error, {:linea_invalida, _n}} -> {:error, :archivo_invalido}
      {:error, razon} -> {:error, razon}
    end
  end

  # albergues/<id>.csv: id;nombre;zona;capacidad_maxima;ocupacion_actual
  defp albergue_de_linea(linea) when is_binary(linea) do
    with [id, nombre, zona, capacidad, ocupacion] <- CSV.separar(linea),
         {:ok, capacidad} <- Util.parsear_entero_no_negativo(capacidad),
         {:ok, ocupacion} <- Util.parsear_entero_no_negativo(ocupacion),
         {:ok, albergue} <- Albergue.crear(id, nombre, zona, capacidad, ocupacion) do
      {:ok, albergue}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  defp albergue_de_linea(_otro), do: {:error, :linea_invalida}

  defp albergue_to_linea(%Albergue{} = albergue) do
    CSV.unir([
      albergue.id,
      albergue.nombre,
      albergue.zona,
      albergue.capacidad_maxima,
      albergue.ocupacion_actual
    ])
  end

  # albergues/<id>_personas.csv: un documento por línea.
  defp persona_de_linea(linea) when is_binary(linea), do: {:ok, linea}
  defp persona_de_linea(_otro), do: {:error, :linea_invalida}

  defp guardar(%Albergue{id: id} = albergue) do
    documentos = albergue.personas |> MapSet.to_list() |> Enum.sort()

    with :ok <- CSV.escribir(ruta_personas(id), @cabecera_personas, documentos, & &1) do
      CSV.escribir(ruta_albergue(id), @cabecera, [albergue], &albergue_to_linea/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%Albergue{id: id} = inicial) do
    if File.exists?(ruta_albergue(id)) do
      case cargar(id) do
        {:ok, albergue} -> {:ok, albergue}
        {:error, razon} -> {:stop, razon}
      end
    else
      case guardar(inicial) do
        :ok -> {:ok, inicial}
        {:error, razon} -> {:stop, {:persistencia, razon}}
      end
    end
  end

  @impl true
  def handle_call(:consultar, _from, albergue), do: {:reply, {:ok, albergue}, albergue}

  def handle_call(:cupos, _from, albergue) do
    {:reply, {:ok, Albergue.cupos_disponibles(albergue)}, albergue}
  end

  def handle_call({:ingreso, documento}, _from, albergue) do
    aplicar(albergue, Albergue.registrar_ingreso(albergue, documento))
  end

  def handle_call({:salida, documento}, _from, albergue) do
    aplicar(albergue, Albergue.registrar_salida(albergue, documento))
  end

  # Solo se acepta el cambio si se pudo guardar.
  defp aplicar(albergue, {:ok, nuevo}) do
    case guardar(nuevo) do
      :ok -> {:reply, {:ok, nuevo}, nuevo}
      {:error, razon} -> {:reply, {:error, {:persistencia, razon}}, albergue}
    end
  end

  defp aplicar(albergue, {:error, _razon} = error), do: {:reply, error, albergue}

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp via(id), do: {:via, Registry, {@registro, {:albergue, id}}}

  defp llamar(id, mensaje) do
    case Registry.lookup(@registro, {:albergue, id}) do
      [{pid, _valor}] -> llamar_pid(pid, mensaje)
      [] -> {:error, :no_encontrado}
    end
  end

  # El proceso puede morir entre el lookup y la llamada.
  defp llamar_pid(pid, mensaje) do
    GenServer.call(pid, mensaje)
  catch
    :exit, {:noproc, _} -> {:error, :no_encontrado}
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :no_disponible}
  end
end
