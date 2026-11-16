defmodule Emergencias.DemoTest do
  # No es asíncrona: la demostración detiene y vuelve a arrancar la aplicación
  # y cambia `:data_dir` mientras corre.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Emergencias.Demo

  defp app_corriendo? do
    Enum.any?(Application.started_applications(), fn {app, _descripcion, _version} ->
      app == :emergencias
    end)
  end

  # Cuántas necesidades quedaron `:asignada` en el CSV de la demostración.
  defp necesidades_asignadas do
    ruta = Path.join(Demo.carpeta_datos(), "necesidades.csv")
    assert {:ok, contenido} = File.read(ruta)

    contenido
    |> String.split("\n", trim: true)
    |> Enum.count(fn linea -> String.contains?(linea, ";asignada;") end)
  end

  describe "flujo_ejemplo/0" do
    test "recorre los seis pasos y termina bien" do
      {resultado, salida} = with_io(fn -> Demo.flujo_ejemplo() end)

      assert resultado == :ok

      for paso <- 1..6 do
        assert salida =~ "Paso #{paso}:"
      end

      assert salida =~ "assign_resource"
      assert salida =~ "match_pets"
      assert salida =~ "summary"
      assert salida =~ "Demostración terminada."
    end

    test "el conflicto termina con una sola asignación aceptada" do
      {resultado, salida} = with_io(fn -> Demo.flujo_ejemplo() end)

      assert resultado == :ok
      assert salida =~ "Asignaciones aceptadas: 1 de 2"
      assert necesidades_asignadas() == 1
    end

    test "empieza con la carpeta limpia: se puede ejecutar dos veces seguidas" do
      # Sin carpeta limpia, la segunda vez fallaría con :id_duplicado (R001, A01...).
      assert capture_io(fn -> assert Demo.flujo_ejemplo() == :ok end) =~ "Paso 1:"
      assert capture_io(fn -> assert Demo.flujo_ejemplo() == :ok end) =~ "Paso 1:"
    end
  end

  describe "conflicto_concurrente/0" do
    test "ejecuta solo los pasos 2 y 3" do
      {resultado, salida} = with_io(fn -> Demo.conflicto_concurrente() end)

      assert resultado == :ok
      assert salida =~ "Paso 2:"
      assert salida =~ "Paso 3:"
      refute salida =~ "Paso 1:"
      refute salida =~ "Paso 4:"
      refute salida =~ "Paso 6:"
      assert salida =~ "Asignaciones aceptadas: 1 de 2"
    end

    test "en varias ejecuciones seguidas siempre queda una sola asignación" do
      for _vez <- 1..5 do
        {resultado, salida} = with_io(fn -> Demo.conflicto_concurrente() end)

        assert resultado == :ok
        assert salida =~ "Asignaciones aceptadas: 1 de 2"
        assert necesidades_asignadas() == 1
      end
    end
  end

  describe "entorno" do
    test "deja :data_dir y la aplicación como estaban" do
      carpeta_antes = Application.fetch_env(:emergencias, :data_dir)
      arriba_antes? = app_corriendo?()

      assert capture_io(fn -> Demo.conflicto_concurrente() end) =~ "DEMOSTRACIÓN"

      assert Application.fetch_env(:emergencias, :data_dir) == carpeta_antes
      assert app_corriendo?() == arriba_antes?
    end

    test "no borra ni modifica la carpeta de datos normal" do
      assert {:ok, carpeta} = Application.fetch_env(:emergencias, :data_dir)
      marcador = Path.join(carpeta, "marcador_demo.txt")

      assert :ok = File.mkdir_p(carpeta)
      assert :ok = File.write(marcador, "no me borres")
      on_exit(fn -> File.rm(marcador) end)

      assert capture_io(fn -> Demo.flujo_ejemplo() end) =~ "Demostración terminada."

      assert File.read(marcador) == {:ok, "no me borres"}
      refute File.exists?(Path.join(carpeta, "necesidades.csv"))
    end
  end
end
