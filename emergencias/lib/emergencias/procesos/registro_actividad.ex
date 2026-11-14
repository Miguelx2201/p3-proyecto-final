defmodule Emergencias.Procesos.RegistroActividad do
  @moduledoc """
  Proceso plano (sin `GenServer`) que registra la actividad de cada usuario.

  Demuestra el paso de mensajes con `spawn_link`, `send` y `receive`:

    * `registrar/3` es asíncrono: envía `{:registrar, actividad}` y no espera respuesta.
    * `listar/1` envía `{:listar, self(), usuario}` y espera `{:actividades, lista}`.

  El estado del proceso es la lista de actividades (la más reciente primero).
  Cada actividad registrada se agrega también a `actividad.csv`; al iniciar se
  carga lo que ya hubiera en ese archivo.

  Ninguna función lanza excepciones.
  """

  require Logger

  alias Emergencias.CSV
  alias Emergencias.Dominio.Actividad

  @timeout 5_000

  @doc """
  Inicia el proceso y lo registra con el nombre del módulo.

  Devuelve `{:ok, pid}`, `{:error, :ya_iniciado}` si el nombre ya está
  registrado, o `{:error, razon}` si `actividad.csv` no se puede leer.
  """
  def start_link(_opts \\ []) do
    case Process.whereis(__MODULE__) do
      nil -> iniciar()
      _pid -> {:error, :ya_iniciado}
    end
  end

  @doc "Especificación para ponerlo bajo un supervisor."
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @doc """
  Registra la actividad de un usuario. Es asíncrono: devuelve `:ok` en cuanto
  envía el mensaje, sin esperar a que se procese.

  `resultado` puede ser `:ok`, `{:ok, valor}`, `{:error, razon}` o el texto
  `"ok"` / `"error:razon"`.

  Errores: los de `Emergencias.Dominio.Actividad.nuevo/3` y `:no_iniciado`.
  """
  def registrar(usuario, comando, resultado) do
    with {:ok, actividad} <- Actividad.nuevo(usuario, comando, resultado),
         {:ok, pid} <- buscar_proceso() do
      send(pid, {:registrar, actividad})
      :ok
    end
  end

  @doc """
  Lista las actividades de un usuario (o de todos con `:todos`), de la más
  antigua a la más reciente.

  Devuelve `{:ok, lista}`, `{:error, :timeout}` si el proceso no responde en
  5 segundos, `{:error, :no_iniciado}` o `{:error, :usuario_invalido}`.
  """
  def listar(usuario) when is_binary(usuario) or usuario == :todos do
    with {:ok, pid} <- buscar_proceso() do
      send(pid, {:listar, self(), usuario})

      receive do
        {:actividades, lista} -> {:ok, lista}
      after
        @timeout -> {:error, :timeout}
      end
    end
  end

  def listar(_otro), do: {:error, :usuario_invalido}

  # ---------------------------------------------------------------------------
  # Proceso
  # ---------------------------------------------------------------------------

  defp iniciar do
    with {:ok, guardadas} <- CSV.leer(ruta(), &Actividad.de_linea/1) do
      estado = Enum.reverse(guardadas)
      pid = spawn_link(fn -> loop(estado) end)
      Process.register(pid, __MODULE__)
      {:ok, pid}
    end
  end

  # Un mensaje por vuelta. Cada rama termina llamando a `loop/1` con el estado
  # nuevo (recursión de cola), y la última rama descarta lo desconocido para que
  # no se acumule en el buzón.
  defp loop(estado) do
    receive do
      {:registrar, %Actividad{} = actividad} ->
        guardar(actividad)
        loop([actividad | estado])

      {:listar, desde, usuario} when is_pid(desde) ->
        send(desde, {:actividades, filtrar(estado, usuario)})
        loop(estado)

      _desconocido ->
        loop(estado)
    end
  end

  defp filtrar(estado, :todos), do: Enum.reverse(estado)

  defp filtrar(estado, usuario) when is_binary(usuario),
    do: estado |> Enum.reverse() |> Enum.filter(fn actividad -> actividad.usuario == usuario end)

  defp filtrar(_estado, _otro), do: []

  # Si el archivo falla, la actividad queda en memoria y el proceso sigue vivo.
  defp guardar(actividad) do
    case CSV.agregar(ruta(), Actividad.cabecera(), actividad, &Actividad.to_linea/1) do
      :ok -> :ok
      {:error, razon} -> Logger.warning("No se pudo guardar la actividad: #{inspect(razon)}")
    end
  end

  defp buscar_proceso do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :no_iniciado}
      pid -> {:ok, pid}
    end
  end

  defp ruta, do: CSV.ruta(Actividad.archivo())
end
