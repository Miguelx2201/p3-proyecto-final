defmodule Emergencias.Procesos.AlberguesSupervisor do
  @moduledoc """
  Supervisor dinámico de los procesos `Emergencias.Procesos.AlbergueServer`
  (uno por albergue, estrategia `:one_for_one`).

  Necesita que `Emergencias.Registry` (`keys: :unique`) ya esté corriendo.
  """

  use DynamicSupervisor

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Procesos.AlbergueServer

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Arranca el proceso de un albergue nuevo.

  Errores: `:albergue_invalido` (no es un `Albergue`), `:id_invalido` (el id no
  sirve como nombre de archivo, ver `AlbergueServer.id_valido?/1`) e
  `:id_duplicado` (ya hay un proceso o ya existe su archivo en disco).
  """
  @spec registrar(Albergue.t()) :: {:ok, pid()} | {:error, term()}
  def registrar(%Albergue{id: id} = albergue) do
    cond do
      not AlbergueServer.id_valido?(id) -> {:error, :id_invalido}
      File.exists?(AlbergueServer.ruta_albergue(id)) -> {:error, :id_duplicado}
      true -> arrancar(albergue)
    end
  end

  def registrar(_otro), do: {:error, :albergue_invalido}

  @doc """
  Estado de todos los albergues que están corriendo, ordenados por id. Los hijos
  que en ese momento se están reiniciando no aparecen.
  """
  @spec listar() :: {:ok, [Albergue.t()]}
  def listar do
    albergues =
      __MODULE__
      |> DynamicSupervisor.which_children()
      |> Enum.flat_map(fn
        {_id, pid, _tipo, _modulos} when is_pid(pid) -> estado_de(pid)
        _otro -> []
      end)
      |> Enum.sort_by(& &1.id)

    {:ok, albergues}
  end

  @doc """
  Arranca un proceso por cada albergue guardado en `albergues/`.

  Devuelve `{:ok, ids}` con los ids que arrancó (los que ya estaban corriendo se
  omiten) o `{:error, {id, razon}}` en el primer archivo que falle.
  """
  @spec cargar_existentes() :: {:ok, [String.t()]} | {:error, {String.t(), term()}}
  def cargar_existentes do
    AlbergueServer.patron_archivos()
    |> Path.wildcard()
    |> Enum.flat_map(fn ruta ->
      case AlbergueServer.id_de_archivo(ruta) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
    |> Enum.sort()
    |> arrancar_ids([])
  end

  defp arrancar_ids([], arrancados), do: {:ok, Enum.reverse(arrancados)}

  defp arrancar_ids([id | resto], arrancados) do
    case arrancar_desde_disco(id) do
      {:ok, _pid} -> arrancar_ids(resto, [id | arrancados])
      :ya_corriendo -> arrancar_ids(resto, arrancados)
      {:error, razon} -> {:error, {id, razon}}
    end
  end

  defp arrancar_desde_disco(id) do
    with {:ok, albergue} <- AlbergueServer.cargar(id) do
      case arrancar(albergue) do
        {:error, :id_duplicado} -> :ya_corriendo
        otro -> otro
      end
    end
  end

  defp arrancar(%Albergue{} = albergue) do
    case DynamicSupervisor.start_child(__MODULE__, {AlbergueServer, albergue}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :id_duplicado}
      {:error, razon} -> {:error, razon}
    end
  end

  defp estado_de(pid) do
    case AlbergueServer.estado(pid) do
      {:ok, albergue} -> [albergue]
      {:error, _razon} -> []
    end
  end
end
