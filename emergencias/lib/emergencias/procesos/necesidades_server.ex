defmodule Emergencias.Procesos.NecesidadesServer do
  @moduledoc """
  Proceso dueño de las necesidades.

  Estado: `%{necesidades: %{id => Necesidad}, contador: n}`.

  Toda la lógica de negocio vive en `Emergencias.Dominio.Necesidad` y en
  `Emergencias.Servicios.NecesidadesServicio`; este módulo solo guarda el estado,
  genera los ids y reescribe `necesidades.csv` tras cada cambio exitoso.

  Como el servidor atiende un mensaje a la vez:

    * dos registros simultáneos nunca reciben el mismo id (el contador vive aquí);
    * si dos solicitudes intentan cerrar la misma necesidad, la segunda recibe
      `{:error, :ya_cerrada}`.

  Si el guardado en disco falla, el cambio se descarta: el estado en memoria
  queda como estaba y quien llamó recibe `{:error, razon}`.
  """

  use GenServer

  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Persistencia
  alias Emergencias.Servicios.NecesidadesServicio
  alias Emergencias.Servicios.Ordenamiento

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc "Inicia el servidor con el nombre del módulo."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Registra una necesidad nueva con el siguiente id (`N001`, `N002`...).

  `asociada_a` puede ser `nil` (queda asociada a su propia zona) o una tupla
  `{:zona | :albergue | :persona, codigo}`. Devuelve `{:ok, necesidad}` o el
  error de `Necesidad.crear/9`.
  """
  @spec registrar(
          atom(),
          String.t() | nil,
          integer(),
          atom(),
          String.t(),
          String.t(),
          String.t(),
          Necesidad.asociada_a() | nil
        ) :: {:ok, Necesidad.t()} | {:error, atom()}
  def registrar(
        tipo,
        tipo_otro,
        cantidad,
        prioridad,
        zona,
        descripcion,
        responsable,
        asociada_a
      ) do
    campos = %{
      tipo: tipo,
      tipo_otro: tipo_otro,
      cantidad: cantidad,
      prioridad: prioridad,
      zona: zona,
      descripcion: descripcion,
      responsable: responsable,
      asociada_a: asociada_a
    }

    GenServer.call(__MODULE__, {:registrar, campos})
  end

  @doc "Busca una necesidad por id."
  @spec obtener(String.t()) :: {:ok, Necesidad.t()} | {:error, :no_encontrado}
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})

  @doc """
  Lista las necesidades que cumplen los filtros (`zona:`, `tipo:`, `prioridad:`,
  `estado:`), ordenadas por prioridad.
  """
  @spec listar(keyword()) :: {:ok, [Necesidad.t()]}
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Necesidades `:pendiente`, ordenadas por prioridad."
  @spec pendientes() :: {:ok, [Necesidad.t()]}
  def pendientes, do: GenServer.call(__MODULE__, :pendientes)

  @doc "Cambia el estado según las transiciones de `Necesidad.cambiar_estado/2`."
  @spec cambiar_estado(String.t(), atom()) :: {:ok, Necesidad.t()} | {:error, atom()}
  def cambiar_estado(id, nuevo), do: GenServer.call(__MODULE__, {:cambiar_estado, id, nuevo})

  @doc "Cancela una necesidad (equivale a `cambiar_estado(id, :cancelada)`)."
  @spec cancelar(String.t()) :: {:ok, Necesidad.t()} | {:error, atom()}
  def cancelar(id), do: GenServer.call(__MODULE__, {:cambiar_estado, id, :cancelada})

  @doc "Suma `cantidad` a la cantidad asignada (ver `Necesidad.registrar_asignacion/2`)."
  @spec registrar_asignacion(String.t(), integer()) :: {:ok, Necesidad.t()} | {:error, atom()}
  def registrar_asignacion(id, cantidad),
    do: GenServer.call(__MODULE__, {:registrar_asignacion, id, cantidad})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    case Persistencia.cargar_necesidades() do
      {:ok, lista} ->
        necesidades = Map.new(lista, fn necesidad -> {necesidad.id, necesidad} end)

        contador =
          lista
          |> Enum.map(fn necesidad -> numero_de_id(necesidad.id) end)
          |> Enum.max(fn -> 0 end)

        {:ok, %{necesidades: necesidades, contador: contador}}

      {:error, razon} ->
        {:stop, razon}
    end
  end

  @impl true
  def handle_call({:registrar, campos}, _from, estado) do
    siguiente = estado.contador + 1
    id = generar_id(siguiente)

    with {:ok, necesidad} <- crear(id, campos),
         nuevo = %{
           estado
           | necesidades: Map.put(estado.necesidades, id, necesidad),
             contador: siguiente
         },
         :ok <- guardar(nuevo) do
      {:reply, {:ok, necesidad}, nuevo}
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, id}, _from, estado), do: {:reply, buscar(estado, id), estado}

  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> NecesidadesServicio.filtrar(filtros)
      |> NecesidadesServicio.ordenar_por_prioridad()

    {:reply, {:ok, lista}, estado}
  end

  def handle_call(:pendientes, _from, estado) do
    {:reply, {:ok, NecesidadesServicio.pendientes(Map.values(estado.necesidades))}, estado}
  end

  def handle_call({:cambiar_estado, id, nuevo}, _from, estado) do
    actualizar(estado, id, fn necesidad -> Necesidad.cambiar_estado(necesidad, nuevo) end)
  end

  def handle_call({:registrar_asignacion, id, cantidad}, _from, estado) do
    actualizar(estado, id, fn necesidad -> Necesidad.registrar_asignacion(necesidad, cantidad) end)
  end

  # ---------------------------------------------------------------------------
  # Ayudas privadas
  # ---------------------------------------------------------------------------

  defp crear(id, campos) do
    Necesidad.crear(
      id,
      campos.tipo,
      campos.tipo_otro,
      campos.descripcion,
      campos.cantidad,
      campos.zona,
      campos.prioridad,
      campos.responsable,
      opciones_asociacion(campos.asociada_a)
    )
  end

  defp opciones_asociacion(nil), do: []
  defp opciones_asociacion(asociada_a), do: [asociada_a: asociada_a]

  defp buscar(estado, id) do
    case Map.fetch(estado.necesidades, id) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, :no_encontrado}
    end
  end

  # Aplica `cambio` (necesidad -> {:ok, nueva} | {:error, razon}) a la necesidad
  # `id` y guarda el CSV. Si algo falla, el estado queda intacto.
  defp actualizar(estado, id, cambio) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, nueva} <- cambio.(necesidad),
         nuevo = %{estado | necesidades: Map.put(estado.necesidades, id, nueva)},
         :ok <- guardar(nuevo) do
      {:reply, {:ok, nueva}, nuevo}
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  # Escribe todas las necesidades, ordenadas por número de id para que el
  # archivo sea estable entre guardados.
  defp guardar(estado) do
    estado.necesidades
    |> Map.values()
    |> Ordenamiento.ordenar(fn a, b -> numero_de_id(a.id) < numero_de_id(b.id) end)
    |> Persistencia.guardar_necesidades()
  end

  defp generar_id(n), do: "N" <> String.pad_leading(Integer.to_string(n), 3, "0")

  # Número de un id con forma "N" + dígitos; cualquier otro id cuenta como 0.
  defp numero_de_id("N" <> digitos) do
    with true <- digitos =~ ~r/^\d+$/,
         {n, ""} <- Integer.parse(digitos) do
      n
    else
      _otro -> 0
    end
  end

  defp numero_de_id(_otro), do: 0
end
