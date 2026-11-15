defmodule Emergencias.Procesos.AlbergueServerTest do
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

  defp registrar(atributos \\ []) do
    {:ok, _pid} = AlberguesSupervisor.registrar(Fabrica.albergue(atributos))
    :ok
  end

  describe "consultar/1 y cupos/1" do
    test "consultar devuelve el albergue" do
      registrar()
      assert {:ok, albergue} = AlbergueServer.consultar("A01")
      assert albergue.id == "A01"
      assert albergue.capacidad_maxima == 100
    end

    test "consultar con id inexistente" do
      assert {:error, :no_encontrado} = AlbergueServer.consultar("X99")
    end

    test "cupos devuelve los cupos libres" do
      registrar(ocupacion_actual: 10)
      assert {:ok, 90} = AlbergueServer.cupos("A01")
    end

    test "cupos con id inexistente" do
      assert {:error, :no_encontrado} = AlbergueServer.cupos("X99")
    end
  end

  describe "ingreso/2" do
    test "ingreso válido suma uno y guarda el documento" do
      registrar()
      assert {:ok, albergue} = AlbergueServer.ingreso("A01", "100")
      assert albergue.ocupacion_actual == 1
      assert MapSet.member?(albergue.personas, "100")
      assert {:ok, 99} = AlbergueServer.cupos("A01")
    end

    test "documento inválido" do
      registrar()
      assert {:error, :documento_invalido} = AlbergueServer.ingreso("A01", "   ")
      assert {:error, :documento_invalido} = AlbergueServer.ingreso("A01", 123)
    end

    test "sin cupo" do
      registrar(capacidad_maxima: 1, ocupacion_actual: 1)
      assert {:error, :sin_cupo} = AlbergueServer.ingreso("A01", "100")
    end

    test "documento ya registrado" do
      registrar()
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")
      assert {:error, :ya_registrado} = AlbergueServer.ingreso("A01", "100")
    end

    test "id inexistente" do
      assert {:error, :no_encontrado} = AlbergueServer.ingreso("X99", "100")
    end

    test "los ingresos concurrentes al mismo albergue se serializan" do
      registrar(capacidad_maxima: 5)

      resultados =
        1..20
        |> Task.async_stream(fn n -> AlbergueServer.ingreso("A01", "doc#{n}") end)
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 5
      assert Enum.count(resultados, &(&1 == {:error, :sin_cupo})) == 15
      assert {:ok, 0} = AlbergueServer.cupos("A01")
    end
  end

  describe "salida/2" do
    test "salida válida resta uno y quita el documento" do
      registrar()
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")
      assert {:ok, albergue} = AlbergueServer.salida("A01", "100")
      assert albergue.ocupacion_actual == 0
      refute MapSet.member?(albergue.personas, "100")
    end

    test "documento inválido" do
      registrar()
      assert {:error, :documento_invalido} = AlbergueServer.salida("A01", "")
    end

    test "la persona no está" do
      registrar()
      assert {:error, :persona_no_esta} = AlbergueServer.salida("A01", "100")
    end

    test "id inexistente" do
      assert {:error, :no_encontrado} = AlbergueServer.salida("X99", "100")
    end
  end

  describe "persistencia" do
    test "al registrar se crean los dos archivos" do
      registrar()

      assert {:ok, contenido} = File.read(AlbergueServer.ruta_albergue("A01"))

      assert contenido ==
               "id;nombre;zona;capacidad_maxima;ocupacion_actual\n" <>
                 "A01;Albergue Norte;centro;100;0\n"

      assert {:ok, "documento\n"} = File.read(AlbergueServer.ruta_personas("A01"))
    end

    test "cada ingreso y cada salida reescriben los archivos" do
      registrar()
      assert {:ok, _} = AlbergueServer.ingreso("A01", "200")
      assert {:ok, _} = AlbergueServer.ingreso("A01", "100")

      assert {:ok, "documento\n100\n200\n"} = File.read(AlbergueServer.ruta_personas("A01"))
      assert {:ok, contenido} = File.read(AlbergueServer.ruta_albergue("A01"))
      assert contenido =~ "A01;Albergue Norte;centro;100;2\n"

      assert {:ok, _} = AlbergueServer.salida("A01", "200")
      assert {:ok, "documento\n100\n"} = File.read(AlbergueServer.ruta_personas("A01"))
    end

    test "si no se puede guardar, responde error y el estado no cambia", %{carpeta: carpeta} do
      registrar()

      # Se reemplaza la carpeta `albergues` por un archivo para que escribir falle.
      carpeta_albergues = Path.join(carpeta, "albergues")
      assert {:ok, _} = File.rm_rf(carpeta_albergues)
      :ok = File.write(carpeta_albergues, "no soy una carpeta")

      assert {:error, {:persistencia, _razon}} = AlbergueServer.ingreso("A01", "100")
      assert {:ok, albergue} = AlbergueServer.consultar("A01")
      assert albergue.ocupacion_actual == 0
      assert MapSet.size(albergue.personas) == 0
    end
  end
end
