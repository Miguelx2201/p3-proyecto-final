defmodule Emergencias.Dominio.SectorTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Sector
  alias Emergencias.Fabrica

  describe "crear/3 con datos válidos" do
    test "crea el sector sin puntos de atención" do
      assert {:ok, %Sector{} = sector} = Sector.crear("S1", "Sector 1", 40)
      assert sector.codigo == "S1"
      assert sector.nombre == "Sector 1"
      assert sector.personas_afectadas == 40
      assert sector.puntos_atencion == []
    end

    test "acepta 0 personas afectadas" do
      assert {:ok, %Sector{personas_afectadas: 0}} = Sector.crear("S1", "Sector 1", 0)
    end

    test "quita los espacios de los extremos en código y nombre" do
      assert {:ok, %Sector{codigo: "S1", nombre: "Sector 1"}} =
               Sector.crear(" S1  ", "  Sector 1 ", 0)
    end

    test "coincide con el sector que construye la fábrica" do
      assert {:ok, Fabrica.sector()} == Sector.crear("S1", "Sector 1", 0)
    end
  end

  describe "crear/3 con datos inválidos" do
    test "rechaza un código vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = Sector.crear("", "Sector 1", 0)
      assert {:error, :texto_vacio} = Sector.crear("   ", "Sector 1", 0)
      assert {:error, :texto_vacio} = Sector.crear(nil, "Sector 1", 0)
      assert {:error, :texto_vacio} = Sector.crear(:s1, "Sector 1", 0)
    end

    test "rechaza un nombre vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = Sector.crear("S1", "", 0)
      assert {:error, :texto_vacio} = Sector.crear("S1", "   ", 0)
      assert {:error, :texto_vacio} = Sector.crear("S1", nil, 0)
      assert {:error, :texto_vacio} = Sector.crear("S1", 123, 0)
    end

    test "rechaza personas afectadas negativas" do
      assert {:error, :cantidad_invalida} = Sector.crear("S1", "Sector 1", -1)
    end

    test "rechaza personas afectadas que no son enteros" do
      assert {:error, :cantidad_invalida} = Sector.crear("S1", "Sector 1", 2.5)
      assert {:error, :cantidad_invalida} = Sector.crear("S1", "Sector 1", "10")
      assert {:error, :cantidad_invalida} = Sector.crear("S1", "Sector 1", nil)
    end
  end

  describe "agregar_punto/2" do
    test "agrega un punto a un sector sin puntos" do
      sector = Fabrica.sector()
      punto = Fabrica.punto_atencion(codigo: "P1")

      assert {:ok, %Sector{puntos_atencion: [^punto]}} = Sector.agregar_punto(sector, punto)
    end

    test "agrega puntos con códigos distintos y conserva el orden" do
      p1 = Fabrica.punto_atencion(codigo: "P1")
      p2 = Fabrica.punto_atencion(codigo: "P2", nombre: "Punto 2")

      assert {:ok, sector} = Sector.agregar_punto(Fabrica.sector(), p1)
      assert {:ok, sector} = Sector.agregar_punto(sector, p2)
      assert sector.puntos_atencion == [p1, p2]
    end

    test "no modifica los demás campos del sector" do
      sector = Fabrica.sector(personas_afectadas: 7)
      punto = Fabrica.punto_atencion()

      assert {:ok, nuevo} = Sector.agregar_punto(sector, punto)
      assert nuevo.codigo == sector.codigo
      assert nuevo.nombre == sector.nombre
      assert nuevo.personas_afectadas == 7
    end

    test "rechaza un punto con un código que el sector ya tiene" do
      punto = Fabrica.punto_atencion(codigo: "P1")
      otro_con_mismo_codigo = Fabrica.punto_atencion(codigo: "P1", nombre: "Otro nombre")

      assert {:ok, sector} = Sector.agregar_punto(Fabrica.sector(), punto)
      assert {:error, :id_duplicado} = Sector.agregar_punto(sector, otro_con_mismo_codigo)
    end

    test "el sector original no cambia después de un intento fallido" do
      punto = Fabrica.punto_atencion(codigo: "P1")
      {:ok, sector} = Sector.agregar_punto(Fabrica.sector(), punto)

      assert {:error, :id_duplicado} = Sector.agregar_punto(sector, punto)
      assert sector.puntos_atencion == [punto]
    end

    test "rechaza algo que no es un punto de atención" do
      sector = Fabrica.sector()

      assert {:error, :punto_invalido} = Sector.agregar_punto(sector, nil)
      assert {:error, :punto_invalido} = Sector.agregar_punto(sector, "P1")
      assert {:error, :punto_invalido} = Sector.agregar_punto(sector, Fabrica.sector())
    end
  end
end
