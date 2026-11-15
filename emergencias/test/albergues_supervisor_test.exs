defmodule Emergencias.Procesos.AlberguesSupervisorTest do
  use ExUnit.Case, async: false

  alias Emergencias.Fabrica
  alias Emergencias.Procesos.AlbergueServer
  alias Emergencias.Procesos.AlberguesSupervisor

  setup do
    carpeta =
      Path.join(
        System.tmp_dir() || "/tmp",
        "emergencias_test_#{System.unique_integer([:positive])}"
      )

    :ok = File.mkdir_p(carpeta)
    anterior = Application.get_env(:emergencias, :data_dir)
    Application.put_env(:emergencias, :data_dir, carpeta)

    on_exit(fn ->
      restaurar(anterior)
      File.rm_rf(carpeta)
    end)

    iniciar_si_falta(Emergencias.Registry, {Registry, keys: :unique, name: Emergencias.Registry})
    iniciar_si_falta(AlberguesSupervisor, AlberguesSupervisor)
    detener_hijos()

    {:ok, carpeta: carpeta}
  end

  defp iniciar_si_falta(nombre, spec) do
    case Process.whereis(nombre) do
      nil ->
        {:ok, _pid} = start_supervised(spec)
        :ok

      _pid ->
        :ok
    end
  end

  defp detener_hijos do
    for {_id, pid, _tipo, _modulos} <- DynamicSupervisor.which_children(AlberguesSupervisor),
        is_pid(pid) do
      DynamicSupervisor.terminate_child(AlberguesSupervisor, pid)
    end

    :ok
  end

  defp restaurar(nil), do: Application.delete_env(:emergencias, :data_dir)
  defp restaurar(valor), do: Application.put_env(:emergencias, :data_dir, valor)

  describe "registrar/1" do
    test "arranca un proceso para un albergue válido" do
      assert {:ok, pid} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))
      assert is_pid(pid)
      assert {:ok, albergue} = AlbergueServer.consultar("A01")
      assert albergue.nombre == "Albergue Norte"
    end

    test "id duplicado" do
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))

      assert {:error, :id_duplicado} =
               AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01", nombre: "Otro"))
    end

    test "id que no sirve como nombre de archivo" do
      for id <- ["../x", "a/b", "", "A01_personas", 5] do
        assert {:error, :id_invalido} = AlberguesSupervisor.registrar(Fabrica.albergue(id: id))
      end
    end

    test "algo que no es un albergue" do
      assert {:error, :albergue_invalido} = AlberguesSupervisor.registrar(%{id: "A01"})
      assert {:error, :albergue_invalido} = AlberguesSupervisor.registrar(nil)
    end
  end

  describe "listar/0" do
    test "sin albergues devuelve lista vacía" do
      assert {:ok, []} = AlberguesSupervisor.listar()
    end

    test "devuelve el estado de cada albergue ordenado por id" do
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A02"))
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")

      assert {:ok, [a1, a2]} = AlberguesSupervisor.listar()
      assert {a1.id, a1.ocupacion_actual} == {"A01", 1}
      assert {a2.id, a2.ocupacion_actual} == {"A02", 0}
    end
  end

  describe "reinicio" do
    test "el supervisor reinicia un proceso muerto con sus datos" do
      assert {:ok, pid1} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A02"))
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")
      assert {:ok, _} = AlbergueServer.ingreso("A02", "200")

      referencia = Process.monitor(pid1)
      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^referencia, :process, ^pid1, :killed}

      pid2 = esperar_nuevo_pid("A01", pid1, 50)
      assert pid2 != pid1

      assert {:ok, albergue} = AlbergueServer.consultar("A01")
      assert albergue.ocupacion_actual == 1
      assert MapSet.member?(albergue.personas, "100")
      assert {:error, :ya_registrado} = AlbergueServer.ingreso("A01", "100")

      # El otro albergue no se tocó.
      assert {:ok, otro} = AlbergueServer.consultar("A02")
      assert MapSet.member?(otro.personas, "200")
    end
  end

  describe "cargar_existentes/0" do
    test "sin carpeta de albergues no arranca nada" do
      assert {:ok, []} = AlberguesSupervisor.cargar_existentes()
    end

    test "arranca un proceso por cada albergue guardado, con sus datos" do
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A02"))
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")

      detener_hijos()
      assert {:error, :no_encontrado} = AlbergueServer.consultar("A01")

      assert {:ok, ["A01", "A02"]} = AlberguesSupervisor.cargar_existentes()

      assert {:ok, albergue} = AlbergueServer.consultar("A01")
      assert albergue.ocupacion_actual == 1
      assert MapSet.member?(albergue.personas, "100")
      assert {:ok, _} = AlbergueServer.consultar("A02")
    end

    test "omite los albergues que ya están corriendo" do
      assert {:ok, _} = AlberguesSupervisor.registrar(Fabrica.albergue(id: "A01"))
      assert {:ok, []} = AlberguesSupervisor.cargar_existentes()
    end

    test "un archivo corrupto devuelve error con el id" do
      ruta = AlbergueServer.ruta_albergue("B01")
      :ok = File.mkdir_p(Path.dirname(ruta))
      :ok = File.write(ruta, "cabecera\nbasura\n")

      assert {:error, {"B01", :archivo_invalido}} = AlberguesSupervisor.cargar_existentes()
    end
  end

  defp esperar_nuevo_pid(_id, _viejo, 0), do: flunk("el supervisor no reinició el proceso")

  defp esperar_nuevo_pid(id, viejo, intentos) do
    case Registry.lookup(Emergencias.Registry, {:albergue, id}) do
      [{pid, _valor}] when pid != viejo ->
        pid

      _otro ->
        Process.sleep(20)
        esperar_nuevo_pid(id, viejo, intentos - 1)
    end
  end
end
