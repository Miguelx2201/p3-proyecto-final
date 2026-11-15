defmodule Emergencias.SupervisionTest do
  @moduledoc """
  Supervisión y persistencia: un proceso que muere se reinicia con sus datos, y
  los datos sobreviven a un reinicio completo de la aplicación.

  Los servidores tienen nombre global, por eso `async: false`.
  """

  use ExUnit.Case, async: false

  alias Emergencias.Procesos.AlbergueServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.Procesos.UsuariosServer
  alias Emergencias.Persistencia
  alias Emergencias.TestHelperApp, as: App

  setup do
    on_exit(&App.detener_y_limpiar/0)
    :ok = App.reiniciar()
    {:ok, usuario} = App.preparar_escenario()
    %{usuario: usuario}
  end

  test "6. si RecursosServer muere, el supervisor lo reinicia y los datos siguen", %{
    usuario: usuario
  } do
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 50)
    {:ok, _movimientos} = Emergencias.remove_stock(usuario, "R001", 10)
    {:ok, _necesidad} = App.registrar_necesidad_agua(usuario, 30)

    anterior = Process.whereis(RecursosServer)
    necesidades = Process.whereis(NecesidadesServer)
    supervisor = Process.whereis(Emergencias.Supervisor)
    assert is_pid(anterior)

    Process.exit(anterior, :kill)

    # Espera a que aparezca un proceso nuevo con el mismo nombre (sin un sleep fijo).
    assert {:ok, nuevo} = App.esperar(fn -> reemplazo(anterior) end)
    assert nuevo != anterior
    assert Process.alive?(nuevo)

    # El estado se reconstruyó desde los CSV.
    assert {:ok, recurso} = RecursosServer.obtener("R001")
    assert recurso.cantidad_disponible == 40
    assert {:ok, [guardado]} = Persistencia.cargar_recursos()
    assert guardado.cantidad_disponible == 40
    assert {:ok, [movimiento]} = RecursosServer.historial("R001")
    assert movimiento.tipo == :salida
    assert movimiento.cantidad == 10

    # one_for_one: los demás procesos no se tocaron.
    assert Process.whereis(NecesidadesServer) == necesidades
    assert Process.whereis(Emergencias.Supervisor) == supervisor

    # Y el servidor reiniciado sigue funcionando.
    assert {:ok, %{recurso: recurso}} = Emergencias.add_stock(usuario, "R001", 5)
    assert recurso.cantidad_disponible == 45
  end

  test "7. los datos persisten al reiniciar la aplicación sin borrar la carpeta", %{
    usuario: usuario
  } do
    {:ok, _zona} = Emergencias.register_sector(usuario, "centro", "S1", "Sector 1", 100)
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 50)
    {:ok, necesidad} = App.registrar_necesidad_agua(usuario, 30)
    {:ok, _asignacion} = Emergencias.assign_resource(usuario, necesidad.id, :agua, 20)
    {:ok, _albergue} = Emergencias.register_shelter(usuario, "A01", "Albergue Norte", "centro", 5)
    {:ok, [documento]} = App.reportar_personas(usuario, 1)
    {:ok, _albergue} = Emergencias.register_entry(usuario, "A01", documento)

    {:ok, _mensaje} =
      Emergencias.send_family_message(
        usuario,
        documento,
        "Estamos bien, te esperamos en el albergue"
      )

    :ok = App.reiniciar(borrar_datos: false)

    # El usuario sigue registrado: se autentica con su contraseña.
    assert {:ok, usuario} = Emergencias.connect("laura", App.contrasena(), :coordinador, "centro")

    assert {:error, :credenciales_invalidas} =
             Emergencias.connect("laura", "otra", :coordinador, "centro")

    assert {:ok, _usuario} = UsuariosServer.obtener("laura")

    assert {:ok, zona} = Emergencias.zone_status(usuario, "centro")
    assert length(zona.sectores) == 1

    assert {:ok, recurso} = RecursosServer.obtener("R001")
    assert recurso.cantidad_disponible == 30

    assert {:ok, necesidad} = NecesidadesServer.obtener(necesidad.id)
    assert necesidad.cantidad_asignada == 20

    assert {:ok, persona} = PersonasServer.obtener(documento)
    assert persona.estado == :en_albergue

    assert {:ok, [mensaje]} = Emergencias.list_family_messages(usuario, documento)
    assert mensaje.contenido == "Estamos bien, te esperamos en el albergue"

    # Los albergues se cargan en una tarea aparte al arrancar: se espera a que estén.
    assert {:ok, albergue} = App.esperar(fn -> albergue_cargado("A01") end)
    assert albergue.ocupacion_actual == 1
    assert MapSet.member?(albergue.personas, documento)

    # Los contadores de ids continúan desde lo guardado: no se repite N001.
    assert {:ok, siguiente} = App.registrar_necesidad_agua(usuario, 10)
    assert siguiente.id != necesidad.id
  end

  test "reiniciar/0 sin opciones sí borra los datos", %{usuario: usuario} do
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 50)

    :ok = App.reiniciar()

    assert {:ok, []} = RecursosServer.listar()
    assert {:error, :no_encontrado} = UsuariosServer.obtener("laura")
  end

  # Pid nuevo registrado con el nombre, o `nil` mientras no haya reemplazo.
  defp reemplazo(anterior) do
    case Process.whereis(RecursosServer) do
      pid when is_pid(pid) and pid != anterior -> pid
      _otro -> nil
    end
  end

  defp albergue_cargado(id) do
    case AlbergueServer.consultar(id) do
      {:ok, albergue} -> albergue
      {:error, _razon} -> nil
    end
  end
end
