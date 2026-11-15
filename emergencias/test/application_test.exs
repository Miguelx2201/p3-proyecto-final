defmodule Emergencias.ApplicationTest do
  # Los procesos tienen nombre global, así que las pruebas no pueden ser async.
  use ExUnit.Case, async: false

  alias Emergencias.Procesos.AlberguesSupervisor
  alias Emergencias.Procesos.MascotasServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.Procesos.RegistroActividad
  alias Emergencias.Procesos.UsuariosServer
  alias Emergencias.Procesos.ZonasServer

  # Ids de los hijos en el orden en que se arrancan (sin la tarea de carga).
  @esperados [
    Emergencias.Registry,
    RegistroActividad,
    UsuariosServer,
    ZonasServer,
    NecesidadesServer,
    RecursosServer,
    PersonasServer,
    MascotasServer,
    AlberguesSupervisor
  ]

  setup do
    # `mix test` corre con --no-start: aquí se arranca el árbol completo.
    _ = Application.stop(:emergencias)

    datos = Application.fetch_env!(:emergencias, :data_dir)
    # Nunca se borra una carpeta que no sea de pruebas.
    assert String.starts_with?(datos, "tmp/")
    File.rm_rf(datos)
    File.mkdir_p(datos)

    {:ok, _apps} = Application.ensure_all_started(:emergencias)
    on_exit(fn -> Application.stop(:emergencias) end)
    :ok
  end

  describe "árbol de supervisión" do
    test "lista los hijos esperados, en orden y todos vivos" do
      hijos = Supervisor.which_children(Emergencias.Supervisor)

      # which_children/1 devuelve el último hijo arrancado primero.
      ids = hijos |> Enum.reverse() |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == Task))

      assert ids == @esperados

      for {id, pid, _tipo, _modulos} <- hijos, id != Task do
        assert is_pid(pid), "#{inspect(id)} no está corriendo"
      end
    end

    test "la tarea de carga de albergues termina y no queda como hijo" do
      assert esperar(fn -> not Enum.any?(hijos_ids(), &(&1 == Task)) end)
      assert {:ok, []} = AlberguesSupervisor.listar()
    end

    test "usa la estrategia :one_for_one" do
      # Con :one_for_one, matar un hijo no reinicia a sus hermanos.
      antes = pids([UsuariosServer, ZonasServer, MascotasServer])
      matar_y_esperar(RecursosServer)

      assert pids([UsuariosServer, ZonasServer, MascotasServer]) == antes
    end
  end

  describe "reinicio de RecursosServer" do
    test "el supervisor lo reinicia y los datos persistidos siguen ahí" do
      assert {:ok, original} =
               RecursosServer.registrar(
                 "R001",
                 "Agua embotellada",
                 :agua,
                 100,
                 "litros",
                 "Bodega central",
                 "centro"
               )

      viejo = Process.whereis(RecursosServer)
      nuevo = matar_y_esperar(RecursosServer)

      assert is_pid(nuevo)
      refute nuevo == viejo

      assert {:ok, recuperado} = RecursosServer.obtener("R001")
      campos = [:id, :nombre, :categoria, :zona, :ubicacion]
      assert Map.take(recuperado, campos) == Map.take(original, campos)
    end
  end

  # -- Ayudas -----------------------------------------------------------------

  defp hijos_ids do
    Emergencias.Supervisor |> Supervisor.which_children() |> Enum.map(&elem(&1, 0))
  end

  defp pids(nombres), do: Enum.map(nombres, &Process.whereis/1)

  # Mata el proceso registrado y espera a que el supervisor arranque otro.
  defp matar_y_esperar(nombre) do
    viejo = Process.whereis(nombre)
    ref = Process.monitor(viejo)
    Process.exit(viejo, :kill)
    assert_receive {:DOWN, ^ref, :process, ^viejo, :killed}

    assert esperar(fn ->
             pid = Process.whereis(nombre)
             is_pid(pid) and pid != viejo
           end)

    Process.whereis(nombre)
  end

  defp esperar(condicion, intentos \\ 100)
  defp esperar(_condicion, 0), do: false

  defp esperar(condicion, intentos) do
    if condicion.() do
      true
    else
      Process.sleep(20)
      esperar(condicion, intentos - 1)
    end
  end
end
