defmodule Emergencias.Procesos.MascotasServer do
  @moduledoc """
  Proceso dueño de los reportes de mascotas perdidas y encontradas.

  Es el único proceso que escribe `mascotas.csv`. Todas las operaciones pasan
  por él, así que cada cambio es atómico respecto a los demás clientes.

  Estado: `%{reportes: %{id => Mascota}, contador: n}`. Los ids son `M001`,
  `M002`, etc.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o
  `{:error, razon}`.

  Cada operación que cambia datos primero guarda `mascotas.csv` y solo si el
  guardado sale bien actualiza el estado del proceso. Si el guardado falla se
  devuelve `{:error, razon}` y el estado queda como estaba.

  Todas las funciones del cliente aceptan, opcionalmente, el proceso como
  primer argumento (pid o nombre). Si se omite se usa el proceso registrado
  con el nombre de este módulo.
  """

  use GenServer

  alias Emergencias.Dominio.{Coincidencia, Mascota}
  alias Emergencias.{Persistencia, Util}

  # Mismo umbral por defecto de `Coincidencia.buscar/3`.
  @umbral_busqueda 60

  @type servidor :: GenServer.server()

  # ---------------------------------------------------------------------------
  # API del cliente
  # ---------------------------------------------------------------------------

  @doc """
  Inicia el proceso y carga `mascotas.csv`.

  Opciones: `:name` (por defecto el nombre del módulo; con `nil` el proceso no
  se registra). Si el archivo está corrupto devuelve `{:error, razon}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opciones \\ []) when is_list(opciones) do
    case Keyword.get(opciones, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, :ok)
      nombre -> GenServer.start_link(__MODULE__, :ok, name: nombre)
    end
  end

  @doc """
  Crea un reporte `:activa` con el siguiente id (`M001`, `M002`...) y guarda
  `mascotas.csv`.

  Devuelve `{:ok, mascota}` o el error de `Mascota.crear/9`
  (`:tipo_invalido`, `:tamano_invalido`, `:especie_vacia`, `:color_vacio`,
  `:contacto_vacio`). Un reporte inválido no consume id.
  """
  def reportar(
        servidor \\ __MODULE__,
        tipo,
        especie,
        nombre,
        caracteristicas,
        color,
        tamano,
        zona,
        contacto
      ) do
    GenServer.call(
      servidor,
      {:reportar, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}
    )
  end

  @doc """
  Lista los reportes que cumplan todos los filtros, ordenados por id.

  `filtros` es una keyword list o un mapa con las claves `:especie`, `:zona`
  (texto, sin distinguir mayúsculas ni tildes) y `:estado` (átomo o texto de
  `Mascota.estados/0`). Un filtro con valor `nil` se ignora.

  Errores: `{:error, :filtros_invalidos}` si `filtros` no es keyword ni mapa,
  `{:error, :filtro_invalido}` si hay una clave desconocida o un valor que no
  es texto, y `{:error, :estado_invalido}` si el estado no existe.
  """
  @spec consultar(servidor(), keyword() | map()) :: {:ok, [Mascota.t()]} | {:error, atom()}
  def consultar(servidor \\ __MODULE__, filtros) do
    GenServer.call(servidor, {:consultar, filtros})
  end

  @doc """
  Busca coincidencias entre las mascotas `:perdida` y las `:encontrada` que
  estén `:activa`, con `Coincidencia.buscar/3`. No cambia ningún estado.

  Devuelve `{:ok, [%{perdida_id: _, encontrada_id: _, puntaje: _}]}`.
  """
  @spec buscar_coincidencias(servidor()) :: {:ok, [map()]}
  def buscar_coincidencias(servidor \\ __MODULE__) do
    GenServer.call(servidor, :buscar_coincidencias)
  end

  @doc """
  Pasa la mascota perdida y la encontrada de `:activa` a
  `:posible_coincidencia` en una sola llamada (todo o nada).

  Devuelve `{:ok, {perdida, encontrada}}` o `{:error, razon}`:
  `:no_encontrada`, `:tipos_invalidos`, `:ya_resuelta` o
  `:transicion_invalida` (por ejemplo, si alguna ya es posible coincidencia).
  """
  @spec registrar_posible_coincidencia(servidor(), String.t(), String.t()) ::
          {:ok, {Mascota.t(), Mascota.t()}} | {:error, atom()}
  def registrar_posible_coincidencia(servidor \\ __MODULE__, id_perdida, id_encontrada) do
    GenServer.call(servidor, {:registrar_posible, id_perdida, id_encontrada})
  end

  @doc """
  Pasa la mascota perdida y la encontrada a `:resuelta` en una sola llamada
  (todo o nada).

  Devuelve `{:ok, {perdida, encontrada}}` o `{:error, razon}`:
  `:no_encontrada`, `:tipos_invalidos` (la primera no es `:perdida` o la
  segunda no es `:encontrada`) o `:ya_resuelta` (alguna ya estaba resuelta; no
  se cambia ninguna).
  """
  @spec confirmar_coincidencia(servidor(), String.t(), String.t()) ::
          {:ok, {Mascota.t(), Mascota.t()}} | {:error, atom()}
  def confirmar_coincidencia(servidor \\ __MODULE__, id_perdida, id_encontrada) do
    GenServer.call(servidor, {:confirmar, id_perdida, id_encontrada})
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    case Persistencia.cargar_mascotas() do
      {:ok, mascotas} ->
        reportes = Map.new(mascotas, fn mascota -> {mascota.id, mascota} end)
        {:ok, %{reportes: reportes, contador: ultimo_numero(mascotas)}}

      {:error, razon} ->
        {:stop, razon}
    end
  end

  @impl true
  def handle_call(
        {:reportar, tipo, especie, nombre, carac, color, tamano, zona, contacto},
        _from,
        estado
      ) do
    numero = estado.contador + 1

    case Mascota.crear(
           formatear_id(numero),
           tipo,
           especie,
           nombre,
           carac,
           color,
           tamano,
           zona,
           contacto
         ) do
      {:ok, mascota} ->
        reportes = Map.put(estado.reportes, mascota.id, mascota)
        confirmar_cambio(%{estado | reportes: reportes, contador: numero}, estado, {:ok, mascota})

      {:error, _razon} = error ->
        {:reply, error, estado}
    end
  end

  def handle_call({:consultar, filtros}, _from, estado) do
    {:reply, consultar_reportes(estado.reportes, filtros), estado}
  end

  def handle_call(:buscar_coincidencias, _from, estado) do
    perdidas = activas(estado.reportes, :perdida)
    encontradas = activas(estado.reportes, :encontrada)
    {:reply, {:ok, Coincidencia.buscar(perdidas, encontradas, @umbral_busqueda)}, estado}
  end

  def handle_call({:registrar_posible, id_perdida, id_encontrada}, _from, estado) do
    cambiar_pareja(estado, id_perdida, id_encontrada, :posible_coincidencia)
  end

  def handle_call({:confirmar, id_perdida, id_encontrada}, _from, estado) do
    cambiar_pareja(estado, id_perdida, id_encontrada, :resuelta)
  end

  # ---------------------------------------------------------------------------
  # Cambios de estado de una pareja
  # ---------------------------------------------------------------------------

  # Calcula las dos mascotas nuevas sin tocar el estado; solo si las dos
  # transiciones son válidas se guarda y se confirma el cambio (todo o nada).
  defp cambiar_pareja(estado, id_perdida, id_encontrada, destino) do
    with {:ok, perdida, encontrada} <- obtener_pareja(estado, id_perdida, id_encontrada),
         {:ok, perdida} <- Mascota.cambiar_estado(perdida, destino),
         {:ok, encontrada} <- Mascota.cambiar_estado(encontrada, destino) do
      reportes =
        estado.reportes
        |> Map.put(perdida.id, perdida)
        |> Map.put(encontrada.id, encontrada)

      confirmar_cambio(%{estado | reportes: reportes}, estado, {:ok, {perdida, encontrada}})
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  defp obtener_pareja(estado, id_perdida, id_encontrada) do
    with {:ok, perdida} <- buscar_reporte(estado, id_perdida),
         {:ok, encontrada} <- buscar_reporte(estado, id_encontrada) do
      if perdida.tipo == :perdida and encontrada.tipo == :encontrada,
        do: {:ok, perdida, encontrada},
        else: {:error, :tipos_invalidos}
    end
  end

  defp buscar_reporte(estado, id) do
    case Map.fetch(estado.reportes, id) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, :no_encontrada}
    end
  end

  # Guarda el CSV antes de adoptar el estado nuevo.
  defp confirmar_cambio(nuevo, anterior, respuesta) do
    case guardar(nuevo) do
      :ok -> {:reply, respuesta, nuevo}
      {:error, _razon} = error -> {:reply, error, anterior}
    end
  end

  defp guardar(estado) do
    mascotas = Enum.sort_by(Map.values(estado.reportes), &clave_id/1)
    Persistencia.guardar_mascotas(mascotas)
  end

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  defp activas(reportes, tipo) do
    reportes
    |> Map.values()
    |> Enum.filter(fn mascota -> mascota.tipo == tipo and mascota.estado == :activa end)
    |> Enum.sort_by(&clave_id/1)
  end

  defp consultar_reportes(reportes, filtros) do
    with {:ok, lista} <- normalizar_filtros(filtros),
         {:ok, predicados} <- construir_predicados(lista) do
      mascotas =
        reportes
        |> Map.values()
        |> Enum.filter(fn mascota -> Enum.all?(predicados, fn pred -> pred.(mascota) end) end)
        |> Enum.sort_by(&clave_id/1)

      {:ok, mascotas}
    end
  end

  defp normalizar_filtros(filtros) when is_map(filtros) and not is_struct(filtros) do
    {:ok, Map.to_list(filtros)}
  end

  defp normalizar_filtros(filtros) when is_list(filtros) do
    if Keyword.keyword?(filtros), do: {:ok, filtros}, else: {:error, :filtros_invalidos}
  end

  defp normalizar_filtros(_otro), do: {:error, :filtros_invalidos}

  defp construir_predicados(filtros) do
    Enum.reduce_while(filtros, {:ok, []}, fn filtro, {:ok, acumulado} ->
      case predicado(filtro) do
        {:ok, pred} -> {:cont, {:ok, [pred | acumulado]}}
        :omitir -> {:cont, {:ok, acumulado}}
        {:error, _razon} = error -> {:halt, error}
      end
    end)
  end

  defp predicado({_clave, nil}), do: :omitir

  defp predicado({clave, valor}) when clave in [:especie, :zona] and is_binary(valor) do
    buscado = normalizar(valor)
    {:ok, fn mascota -> normalizar(Map.get(mascota, clave)) == buscado end}
  end

  defp predicado({:estado, valor}) do
    with {:ok, estado} <- convertir_estado(valor) do
      {:ok, fn mascota -> mascota.estado == estado end}
    end
  end

  defp predicado(_otro), do: {:error, :filtro_invalido}

  defp convertir_estado(estado) when is_atom(estado) do
    if estado in Mascota.estados(), do: {:ok, estado}, else: {:error, :estado_invalido}
  end

  defp convertir_estado(estado) when is_binary(estado) do
    case Util.parsear_enum(estado, Mascota.estados()) do
      {:ok, valor} -> {:ok, valor}
      {:error, _razon} -> {:error, :estado_invalido}
    end
  end

  defp convertir_estado(_otro), do: {:error, :estado_invalido}

  # Minúsculas, sin tildes y sin espacios alrededor (igual que `Coincidencia`).
  defp normalizar(texto) when is_binary(texto) do
    minusculas = texto |> String.trim() |> String.downcase()

    case :unicode.characters_to_nfd_binary(minusculas) do
      descompuesto when is_binary(descompuesto) -> String.replace(descompuesto, ~r/\p{Mn}/u, "")
      _error -> minusculas
    end
  end

  defp normalizar(_otro), do: ""

  # ---------------------------------------------------------------------------
  # Ids
  # ---------------------------------------------------------------------------

  defp formatear_id(numero), do: "M" <> String.pad_leading(Integer.to_string(numero), 3, "0")

  # Ordena por número aunque pase de tres dígitos (M999 antes que M1000).
  defp clave_id(%Mascota{id: id}), do: {String.length(id), id}

  defp ultimo_numero(mascotas) do
    Enum.reduce(mascotas, 0, fn mascota, maximo -> max(maximo, numero_de_id(mascota.id)) end)
  end

  defp numero_de_id("M" <> digitos) do
    case Util.parsear_entero_no_negativo(digitos) do
      {:ok, numero} -> numero
      {:error, _razon} -> 0
    end
  end

  defp numero_de_id(_otro), do: 0
end
