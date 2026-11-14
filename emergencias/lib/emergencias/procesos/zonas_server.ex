defmodule Emergencias.Procesos.ZonasServer do
  @moduledoc """
  GenServer que guarda las zonas con sus sectores y puntos de atención.

  Estado: `%{zonas: %{codigo => Zona}}`.

  Toda la lógica vive en `Emergencias.Dominio.Zona`, `Sector` y `PuntoAtencion`;
  este proceso solo mantiene el mapa, serializa las llamadas y persiste el árbol
  completo con `Emergencias.Persistencia.guardar_zonas/1` después de cada cambio
  exitoso.

  Si el guardado falla, el cambio se descarta: el estado queda igual y la
  llamada devuelve `{:error, razon}`.

  Los códigos de zona y de sector se buscan tal cual (sin recortar espacios ni
  distinguir mayúsculas). Un código que no es texto nunca se encuentra.
  """

  use GenServer

  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Dominio.Sector
  alias Emergencias.Dominio.Zona
  alias Emergencias.Persistencia

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc "Inicia el servidor, registrado con el nombre del módulo."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Registra una zona sin sectores y con 0 personas estimadas.

  Errores: `:id_duplicado` si ya existe una zona con ese código, y los de
  `Zona.crear/4` (`:texto_vacio`, `:nivel_invalido`).
  """
  @spec registrar_zona(term(), term(), term()) :: {:ok, Zona.t()} | {:error, term()}
  def registrar_zona(codigo, nombre, nivel),
    do: GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel})

  @doc """
  Registra un sector en la zona `zona` (su código). Devuelve la zona actualizada.

  Errores: `:no_encontrado` si la zona no existe, y los de `Sector.crear/3`
  (`:texto_vacio`, `:cantidad_invalida`) y `Zona.agregar_sector/2`
  (`:id_duplicado`).
  """
  @spec registrar_sector(term(), term(), term(), term()) :: {:ok, Zona.t()} | {:error, term()}
  def registrar_sector(zona, codigo, nombre, personas),
    do: GenServer.call(__MODULE__, {:registrar_sector, zona, codigo, nombre, personas})

  @doc """
  Registra un punto de atención en el sector `sector` de la zona `zona`.
  Devuelve la zona actualizada.

  Errores: `:no_encontrado` si la zona o el sector no existen, y los de
  `PuntoAtencion.crear/3` (`:texto_vacio`, `:cantidad_invalida`) y
  `Sector.agregar_punto/2` (`:id_duplicado`).
  """
  @spec registrar_punto(term(), term(), term(), term(), term()) ::
          {:ok, Zona.t()} | {:error, term()}
  def registrar_punto(zona, sector, codigo, nombre, personas),
    do: GenServer.call(__MODULE__, {:registrar_punto, zona, sector, codigo, nombre, personas})

  @doc "Busca una zona por código."
  @spec consultar(term()) :: {:ok, Zona.t()} | {:error, :no_encontrado}
  def consultar(codigo), do: GenServer.call(__MODULE__, {:consultar, codigo})

  @doc "Estadísticas de una zona (ver `Zona.estadisticas/1`)."
  @spec estadisticas(term()) :: {:ok, map()} | {:error, :no_encontrado}
  def estadisticas(codigo), do: GenServer.call(__MODULE__, {:estadisticas, codigo})

  @doc """
  Cambia el nivel de afectación de una zona.

  Errores: `:no_encontrado` y `:nivel_invalido`.
  """
  @spec cambiar_nivel(term(), term()) :: {:ok, Zona.t()} | {:error, term()}
  def cambiar_nivel(codigo, nivel),
    do: GenServer.call(__MODULE__, {:cambiar_nivel, codigo, nivel})

  @doc """
  Actualiza la estimación de personas afectadas de una zona.

  Errores: `:no_encontrado` y `:cantidad_invalida`.
  """
  @spec actualizar_personas(term(), term()) :: {:ok, Zona.t()} | {:error, term()}
  def actualizar_personas(codigo, n),
    do: GenServer.call(__MODULE__, {:actualizar_personas, codigo, n})

  @doc "Lista todas las zonas, ordenadas por código."
  @spec listar() :: [Zona.t()]
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Indica si existe una zona con ese código."
  @spec existe?(term()) :: boolean()
  def existe?(codigo), do: GenServer.call(__MODULE__, {:existe, codigo})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    with {:ok, lista} <- Persistencia.cargar_zonas(),
         {:ok, zonas} <- indexar(lista) do
      {:ok, %{zonas: zonas}}
    else
      {:error, razon} -> {:stop, razon}
    end
  end

  @impl true
  def handle_call({:registrar_zona, codigo, nombre, nivel}, _from, estado) do
    with {:ok, zona} <- Zona.crear(codigo, nombre, nivel),
         :ok <- validar_nueva(estado, zona.codigo),
         {:ok, nuevo_estado} <- persistir(estado, zona) do
      {:reply, {:ok, zona}, nuevo_estado}
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  def handle_call({:registrar_sector, zona, codigo, nombre, personas}, _from, estado) do
    modificar(estado, zona, fn actual ->
      with {:ok, sector} <- Sector.crear(codigo, nombre, personas) do
        Zona.agregar_sector(actual, sector)
      end
    end)
  end

  def handle_call({:registrar_punto, zona, sector, codigo, nombre, personas}, _from, estado) do
    modificar(estado, zona, fn actual ->
      with {:ok, punto} <- PuntoAtencion.crear(codigo, nombre, personas) do
        Zona.agregar_punto(actual, sector, punto)
      end
    end)
  end

  def handle_call({:consultar, codigo}, _from, estado),
    do: {:reply, buscar(estado, codigo), estado}

  def handle_call({:estadisticas, codigo}, _from, estado) do
    case buscar(estado, codigo) do
      {:ok, zona} -> {:reply, {:ok, Zona.estadisticas(zona)}, estado}
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  def handle_call({:cambiar_nivel, codigo, nivel}, _from, estado),
    do: modificar(estado, codigo, fn zona -> Zona.cambiar_nivel(zona, nivel) end)

  def handle_call({:actualizar_personas, codigo, n}, _from, estado),
    do: modificar(estado, codigo, fn zona -> Zona.actualizar_personas(zona, n) end)

  def handle_call(:listar, _from, estado), do: {:reply, lista_ordenada(estado.zonas), estado}

  def handle_call({:existe, codigo}, _from, estado),
    do: {:reply, Map.has_key?(estado.zonas, codigo), estado}

  # ---------------------------------------------------------------------------
  # Privadas
  # ---------------------------------------------------------------------------

  defp buscar(estado, codigo) do
    case Map.fetch(estado.zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, :no_encontrado}
    end
  end

  defp validar_nueva(estado, codigo) do
    if Map.has_key?(estado.zonas, codigo), do: {:error, :id_duplicado}, else: :ok
  end

  # Busca la zona, aplica la función pura y persiste. Si algo falla, el estado
  # queda igual.
  defp modificar(estado, codigo, funcion) do
    with {:ok, zona} <- buscar(estado, codigo),
         {:ok, nueva} <- funcion.(zona),
         {:ok, nuevo_estado} <- persistir(estado, nueva) do
      {:reply, {:ok, nueva}, nuevo_estado}
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  defp persistir(estado, zona) do
    zonas = Map.put(estado.zonas, zona.codigo, zona)

    case Persistencia.guardar_zonas(lista_ordenada(zonas)) do
      :ok -> {:ok, %{estado | zonas: zonas}}
      {:error, _razon} = error -> error
    end
  end

  defp lista_ordenada(zonas), do: zonas |> Map.values() |> Enum.sort_by(& &1.codigo)

  defp indexar(lista) do
    Enum.reduce_while(lista, {:ok, %{}}, fn zona, {:ok, acumulado} ->
      if Map.has_key?(acumulado, zona.codigo) do
        {:halt, {:error, :id_duplicado}}
      else
        {:cont, {:ok, Map.put(acumulado, zona.codigo, zona)}}
      end
    end)
  end
end
