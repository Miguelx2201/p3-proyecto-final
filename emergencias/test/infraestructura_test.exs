defmodule Emergencias.InfraestructuraTest do
  use ExUnit.Case, async: true

  alias Emergencias.CSV

  test "las pruebas usan una carpeta de datos separada de data/" do
    assert Application.get_env(:emergencias, :data_dir) == "tmp/test_data"
    assert CSV.ruta("usuarios.csv") == Path.join("tmp/test_data", "usuarios.csv")
  end

  test "test/support se compila en pruebas" do
    assert Code.ensure_loaded?(Emergencias.Fabrica)
  end

  @tag :tmp_dir
  test "cada prueba puede pedir su propia carpeta temporal", %{tmp_dir: dir} do
    assert File.dir?(dir)
    assert :ok = File.write(Path.join(dir, "x.txt"), "hola")
  end
end
