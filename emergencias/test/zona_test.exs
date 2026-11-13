defmodule Emergencias.Dominio.ZonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Zona
  alias Emergencias.Fabrica

  describe "crear/4 con datos válidos" do
    test "crea la zona sin sectores" do
      assert {:ok, %Zona{} = zona} = Zona.crear("centro", "Zona Centro", :critico, 500)
      assert zona.codigo == "centro"
      assert zona.nombre == "Zona Centro"
      assert zona.nivel == :critico
      assert zona.personas_afectadas == 500
      assert zona.sectores == []
    end

    test "las personas afectadas valen 0 por defecto" do
      assert {:ok, %Zona{personas_afectadas: 0}} = Zona.crear("centro", "Zona Centro", :alto)
    end

    test "acepta los cuatro niveles permitidos" do
      for nivel <- [:critico, :alto, :medio, :bajo] do
        assert {:ok, %Zona{nivel: ^nivel}} = Zona.crear("centro", "Zona Centro", nivel)
      end
    end

    test "quita los espacios de los extremos en código y nombre" do
      assert {:ok, %Zona{codigo: "centro", nombre: "Zona Centro"}} =
               Zona.crear(" centro ", "  Zona Centro  ", :medio)
    end

    test "coincide con la zona que construye la fábrica" do
      assert {:ok, Fabrica.zona()} == Zona.crear("centro", "Zona Centro", :critico)
    end
  end

  describe "crear/4 con datos inválidos" do
    test "rechaza un código vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = Zona.crear("", "Zona Centro", :alto)
      assert {:error, :texto_vacio} = Zona.crear("   ", "Zona Centro", :alto)
      assert {:error, :texto_vacio} = Zona.crear(nil, "Zona Centro", :alto)
      assert {:error, :texto_vacio} = Zona.crear(:centro, "Zona Centro", :alto)
    end

    test "rechaza un nombre vacío, en blanco o que no es texto" do
      assert {:error, :texto_vacio} = Zona.crear("centro", "", :alto)
      assert {:error, :texto_vacio} = Zona.crear("centro", "   ", :alto)
      assert {:error, :texto_vacio} = Zona.crear("centro", nil, :alto)
      assert {:error, :texto_vacio} = Zona.crear("centro", 123, :alto)
    end

    test "rechaza un nivel que no está permitido" do
      assert {:error, :nivel_invalido} = Zona.crear("centro", "Zona Centro", :grave)
      assert {:error, :nivel_invalido} = Zona.crear("centro", "Zona Centro", "critico")
      assert {:error, :nivel_invalido} = Zona.crear("centro", "Zona Centro", nil)
    end

    test "rechaza personas afectadas negativas" do
      assert {:error, :cantidad_invalida} = Zona.crear("centro", "Zona Centro", :alto, -1)
    end

    test "rechaza personas afectadas que no son enteros" do
      assert {:error, :cantidad_invalida} = Zona.crear("centro", "Zona Centro", :alto, 1.5)
      assert {:error, :cantidad_invalida} = Zona.crear("centro", "Zona Centro", :alto, "10")
      assert {:error, :cantidad_invalida} = Zona.crear("centro", "Zona Centro", :alto, nil)
    end
  end

  describe "agregar_sector/2" do
    test "agrega un sector a una zona sin sectores" do
      zona = Fabrica.zona()
      sector = Fabrica.sector(codigo: "S1")

      assert {:ok, %Zona{sectores: [^sector]}} = Zona.agregar_sector(zona, sector)
    end

    test "agrega sectores con códigos distintos y conserva el orden" do
      s1 = Fabrica.sector(codigo: "S1")
      s2 = Fabrica.sector(codigo: "S2", nombre: "Sector 2")

      assert {:ok, zona} = Zona.agregar_sector(Fabrica.zona(), s1)
      assert {:ok, zona} = Zona.agregar_sector(zona, s2)
      assert zona.sectores == [s1, s2]
    end

    test "no modifica los demás campos de la zona" do
      zona = Fabrica.zona(nivel: :bajo, personas_afectadas: 90)

      assert {:ok, nueva} = Zona.agregar_sector(zona, Fabrica.sector())
      assert nueva.codigo == zona.codigo
      assert nueva.nombre == zona.nombre
      assert nueva.nivel == :bajo
      assert nueva.personas_afectadas == 90
    end

    test "rechaza un sector con un código que la zona ya tiene" do
      sector = Fabrica.sector(codigo: "S1")
      otro_con_mismo_codigo = Fabrica.sector(codigo: "S1", nombre: "Otro nombre")

      assert {:ok, zona} = Zona.agregar_sector(Fabrica.zona(), sector)
      assert {:error, :id_duplicado} = Zona.agregar_sector(zona, otro_con_mismo_codigo)
    end

    test "la zona original no cambia después de un intento fallido" do
      sector = Fabrica.sector(codigo: "S1")
      {:ok, zona} = Zona.agregar_sector(Fabrica.zona(), sector)

      assert {:error, :id_duplicado} = Zona.agregar_sector(zona, sector)
      assert zona.sectores == [sector]
    end

    test "rechaza algo que no es un sector" do
      zona = Fabrica.zona()

      assert {:error, :sector_invalido} = Zona.agregar_sector(zona, nil)
      assert {:error, :sector_invalido} = Zona.agregar_sector(zona, "S1")
      assert {:error, :sector_invalido} = Zona.agregar_sector(zona, Fabrica.punto_atencion())
    end
  end

  describe "cambiar_nivel/2" do
    test "cambia el nivel a cualquiera de los permitidos" do
      zona = Fabrica.zona(nivel: :critico)

      for nivel <- [:alto, :medio, :bajo, :critico] do
        assert {:ok, %Zona{nivel: ^nivel}} = Zona.cambiar_nivel(zona, nivel)
      end
    end

    test "cambiar al mismo nivel es válido" do
      zona = Fabrica.zona(nivel: :medio)

      assert {:ok, ^zona} = Zona.cambiar_nivel(zona, :medio)
    end

    test "no modifica los demás campos" do
      {:ok, zona} = Zona.agregar_sector(Fabrica.zona(personas_afectadas: 12), Fabrica.sector())

      assert {:ok, nueva} = Zona.cambiar_nivel(zona, :bajo)
      assert %Zona{nueva | nivel: zona.nivel} == zona
    end

    test "rechaza un nivel que no está permitido y deja la zona igual" do
      zona = Fabrica.zona(nivel: :critico)

      assert {:error, :nivel_invalido} = Zona.cambiar_nivel(zona, :grave)
      assert {:error, :nivel_invalido} = Zona.cambiar_nivel(zona, "alto")
      assert {:error, :nivel_invalido} = Zona.cambiar_nivel(zona, nil)
      assert zona.nivel == :critico
    end
  end

  describe "actualizar_personas/2" do
    test "actualiza la estimación de personas afectadas" do
      assert {:ok, %Zona{personas_afectadas: 1200}} =
               Zona.actualizar_personas(Fabrica.zona(), 1200)
    end

    test "acepta 0" do
      zona = Fabrica.zona(personas_afectadas: 50)

      assert {:ok, %Zona{personas_afectadas: 0}} = Zona.actualizar_personas(zona, 0)
    end

    test "no modifica los demás campos" do
      {:ok, zona} = Zona.agregar_sector(Fabrica.zona(), Fabrica.sector())

      assert {:ok, nueva} = Zona.actualizar_personas(zona, 77)
      assert %Zona{nueva | personas_afectadas: zona.personas_afectadas} == zona
    end

    test "rechaza cantidades negativas y deja la zona igual" do
      zona = Fabrica.zona(personas_afectadas: 50)

      assert {:error, :cantidad_invalida} = Zona.actualizar_personas(zona, -1)
      assert zona.personas_afectadas == 50
    end

    test "rechaza cantidades que no son enteros" do
      zona = Fabrica.zona()

      assert {:error, :cantidad_invalida} = Zona.actualizar_personas(zona, 1.5)
      assert {:error, :cantidad_invalida} = Zona.actualizar_personas(zona, "10")
      assert {:error, :cantidad_invalida} = Zona.actualizar_personas(zona, nil)
    end
  end
end
