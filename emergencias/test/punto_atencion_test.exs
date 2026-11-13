defmodule Emergencias.Dominio.PuntoAtencionTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Fabrica

  describe "crear/3 con datos válidos" do
    test "crea el punto con los datos recibidos" do
      assert {:ok, %PuntoAtencion{} = punto} = PuntoAtencion.crear("P1", "Punto 1", 25)
      assert punto.codigo == "P1"
      assert punto.nombre == "Punto 1"
      assert punto.personas_afectadas == 25
    end

    test "acepta 0 personas afectadas" do
      assert {:ok, %PuntoAtencion{personas_afectadas: 0}} =
               PuntoAtencion.crear("P1", "Punto 1", 0)
    end

    test "quita los espacios de los extremos en código y nombre" do
      assert {:ok, %PuntoAtencion{codigo: "P1", nombre: "Punto 1"}} =
               PuntoAtencion.crear("  P1 ", " Punto 1  ", 3)
    end

    test "coincide con el punto que construye la fábrica" do
      assert {:ok, Fabrica.punto_atencion()} == PuntoAtencion.crear("P1", "Punto 1", 0)
    end
  end

  describe "crear/3 con datos inválidos" do
    test "rechaza un código vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = PuntoAtencion.crear("", "Punto 1", 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear("   ", "Punto 1", 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear(nil, "Punto 1", 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear(:p1, "Punto 1", 0)
    end

    test "rechaza un nombre vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = PuntoAtencion.crear("P1", "", 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear("P1", "   ", 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear("P1", nil, 0)
      assert {:error, :texto_vacio} = PuntoAtencion.crear("P1", 123, 0)
    end

    test "rechaza personas afectadas negativas" do
      assert {:error, :cantidad_invalida} = PuntoAtencion.crear("P1", "Punto 1", -1)
    end

    test "rechaza personas afectadas que no son enteros" do
      assert {:error, :cantidad_invalida} = PuntoAtencion.crear("P1", "Punto 1", 1.5)
      assert {:error, :cantidad_invalida} = PuntoAtencion.crear("P1", "Punto 1", "10")
      assert {:error, :cantidad_invalida} = PuntoAtencion.crear("P1", "Punto 1", nil)
    end
  end
end
