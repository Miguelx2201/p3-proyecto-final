defmodule Emergencias.Application do
  @moduledoc """
  Aplicación OTP: arranca el árbol de supervisión del sistema.

  Orden de arranque (cada hijo puede depender de los anteriores):

    1. `Emergencias.Registry` (`keys: :unique`): lo usan los procesos de albergue.
    2. `RegistroActividad`: proceso plano que registra la actividad.
    3. `UsuariosServer`, `ZonasServer`, `NecesidadesServer`, `RecursosServer`,
       `PersonasServer` y `MascotasServer`: un `GenServer` por entidad.
    4. `AlberguesSupervisor`: `DynamicSupervisor` con un `AlbergueServer` por albergue.
    5. Una tarea que, una vez arrancado todo lo anterior, levanta los albergues
       guardados en disco. Es temporal: termina al acabar y no se reinicia.

  Estrategia `:one_for_one`: los servidores son independientes, así que si uno
  falla los demás no se reinician, y cada uno reconstruye su estado desde los
  CSV en `init/1`.
  """

  use Application

  require Logger

  alias Emergencias.Procesos.AlberguesSupervisor
  alias Emergencias.Procesos.MascotasServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.Procesos.RegistroActividad
  alias Emergencias.Procesos.UsuariosServer
  alias Emergencias.Procesos.ZonasServer

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Emergencias.Registry},
      RegistroActividad,
      UsuariosServer,
      ZonasServer,
      NecesidadesServer,
      RecursosServer,
      PersonasServer,
      MascotasServer,
      AlberguesSupervisor,
      {Task, fn -> cargar_albergues() end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Emergencias.Supervisor)
  end

  # Si algún albergue no se puede cargar, la tarea terminaría sin que nadie se
  # entere; por eso se deja el error en el log.
  defp cargar_albergues do
    case AlberguesSupervisor.cargar_existentes() do
      {:ok, _ids} = resultado ->
        resultado

      {:error, {id, razon}} = error ->
        Logger.warning("No se pudo cargar el albergue #{id}: #{inspect(razon)}")
        error
    end
  end
end
