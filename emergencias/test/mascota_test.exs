defmodule Emergencias.Dominio.MascotaTest do
  use ExUnit.Case, async: true

  alias Emergencias.CSV
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Fabrica

  defp crear(cambios \\ []) do
    valores =
      Keyword.merge(
        [
          id: "M001",
          tipo: :perdida,
          especie: "perro",
          nombre: "Luna",
          caracteristicas: "collar rojo",
          color: "negra",
          tamano: :mediano,
          zona: "centro",
          contacto: "3001234567"
        ],
        cambios
      )

    Mascota.crear(
      valores[:id],
      valores[:tipo],
      valores[:especie],
      valores[:nombre],
      valores[:caracteristicas],
      valores[:color],
      valores[:tamano],
      valores[:zona],
      valores[:contacto]
    )
  end

  describe "crear/9" do
    test "crea un reporte válido en estado :activa" do
      assert {:ok, %Mascota{} = m} = crear()

      assert m.id == "M001"
      assert m.tipo == :perdida
      assert m.especie == "perro"
      assert m.nombre == "Luna"
      assert m.caracteristicas == "collar rojo"
      assert m.color == "negra"
      assert m.tamano == :mediano
      assert m.zona == "centro"
      assert m.contacto == "3001234567"
      assert m.estado == :activa
    end

    test "acepta el tipo :encontrada y todos los tamaños" do
      assert {:ok, %Mascota{tipo: :encontrada}} = crear(tipo: :encontrada)

      for tamano <- [:pequeno, :mediano, :grande] do
        assert {:ok, %Mascota{tamano: ^tamano}} = crear(tamano: tamano)
      end
    end

    test "el texto desconocido en el nombre se convierte en nil" do
      assert {:ok, %Mascota{nombre: nil}} = crear(nombre: "desconocido")
      assert {:ok, %Mascota{nombre: nil}} = crear(nombre: "  Desconocido ")
    end

    test "nombre nil o vacío queda en nil" do
      assert {:ok, %Mascota{nombre: nil}} = crear(nombre: nil)
      assert {:ok, %Mascota{nombre: nil}} = crear(nombre: "   ")
    end

    test "características nil o vacías quedan como texto vacío" do
      assert {:ok, %Mascota{caracteristicas: ""}} = crear(caracteristicas: nil)
      assert {:ok, %Mascota{caracteristicas: ""}} = crear(caracteristicas: "")
    end

    test "sanitiza los textos libres para el CSV" do
      assert {:ok, m} = crear(caracteristicas: "collar; rojo\nmancha", nombre: " Luna ")
      assert m.caracteristicas == "collar  rojo mancha"
      assert m.nombre == "Luna"
    end

    test "rechaza un tipo no permitido" do
      assert {:error, :tipo_invalido} = crear(tipo: :robada)
      assert {:error, :tipo_invalido} = crear(tipo: "perdida")
    end

    test "rechaza un tamaño no permitido" do
      assert {:error, :tamano_invalido} = crear(tamano: :gigante)
      assert {:error, :tamano_invalido} = crear(tamano: nil)
    end

    test "rechaza una especie vacía" do
      assert {:error, :especie_vacia} = crear(especie: "   ")
      assert {:error, :especie_vacia} = crear(especie: nil)
    end

    test "rechaza un color vacío" do
      assert {:error, :color_vacio} = crear(color: "")
      assert {:error, :color_vacio} = crear(color: nil)
    end

    test "rechaza un contacto vacío" do
      assert {:error, :contacto_vacio} = crear(contacto: " ")
      assert {:error, :contacto_vacio} = crear(contacto: nil)
    end

    test "un texto que solo tiene ; o saltos de línea cuenta como vacío" do
      assert {:error, :especie_vacia} = crear(especie: ";\n")
    end
  end

  describe "cambiar_estado/2: transiciones válidas" do
    test "activa → posible_coincidencia" do
      m = Fabrica.mascota(estado: :activa)

      assert {:ok, %Mascota{estado: :posible_coincidencia}} =
               Mascota.cambiar_estado(m, :posible_coincidencia)
    end

    test "activa → resuelta" do
      m = Fabrica.mascota(estado: :activa)
      assert {:ok, %Mascota{estado: :resuelta}} = Mascota.cambiar_estado(m, :resuelta)
    end

    test "posible_coincidencia → activa" do
      m = Fabrica.mascota(estado: :posible_coincidencia)
      assert {:ok, %Mascota{estado: :activa}} = Mascota.cambiar_estado(m, :activa)
    end

    test "posible_coincidencia → resuelta" do
      m = Fabrica.mascota(estado: :posible_coincidencia)
      assert {:ok, %Mascota{estado: :resuelta}} = Mascota.cambiar_estado(m, :resuelta)
    end

    test "no modifica la struct original" do
      m = Fabrica.mascota(estado: :activa)
      assert {:ok, _nueva} = Mascota.cambiar_estado(m, :resuelta)
      assert m.estado == :activa
    end
  end

  describe "cambiar_estado/2: transiciones inválidas" do
    test "activa → activa" do
      m = Fabrica.mascota(estado: :activa)
      assert {:error, :transicion_invalida} = Mascota.cambiar_estado(m, :activa)
    end

    test "posible_coincidencia → posible_coincidencia" do
      m = Fabrica.mascota(estado: :posible_coincidencia)

      assert {:error, :transicion_invalida} =
               Mascota.cambiar_estado(m, :posible_coincidencia)
    end

    test "a un estado que no existe" do
      m = Fabrica.mascota(estado: :activa)
      assert {:error, :transicion_invalida} = Mascota.cambiar_estado(m, :perdida)
      assert {:error, :transicion_invalida} = Mascota.cambiar_estado(m, "resuelta")
    end

    test "cerrar dos veces: un reporte resuelto no se vuelve a resolver" do
      m = Fabrica.mascota(estado: :activa)
      assert {:ok, resuelta} = Mascota.cambiar_estado(m, :resuelta)
      assert {:error, :ya_resuelta} = Mascota.cambiar_estado(resuelta, :resuelta)
    end

    test "un reporte resuelto no permite ninguna transición" do
      m = Fabrica.mascota(estado: :resuelta)
      assert {:error, :ya_resuelta} = Mascota.cambiar_estado(m, :activa)
      assert {:error, :ya_resuelta} = Mascota.cambiar_estado(m, :posible_coincidencia)
    end
  end

  describe "CSV" do
    test "la cabecera tiene los 10 campos y el archivo es mascotas.csv" do
      assert Mascota.archivo() == "mascotas.csv"

      assert CSV.separar(Mascota.cabecera()) == [
               "id",
               "tipo",
               "especie",
               "nombre",
               "caracteristicas",
               "color",
               "tamano",
               "zona",
               "contacto",
               "estado"
             ]
    end

    test "a_linea escribe todos los campos en orden" do
      m = Fabrica.mascota(caracteristicas: "collar rojo", estado: :posible_coincidencia)

      assert Mascota.to_linea(m) ==
               "M001;perdida;perro;Luna;collar rojo;negra;mediano;centro;3001234567;posible_coincidencia"
    end

    test "ida y vuelta: de_linea(a_linea(m)) devuelve la misma mascota" do
      m = Fabrica.mascota(caracteristicas: "collar rojo", estado: :resuelta)
      assert {:ok, ^m} = Mascota.de_linea(Mascota.to_linea(m))
    end

    test "un nombre desconocido se guarda vacío y vuelve como nil" do
      m = Fabrica.mascota(nombre: nil)
      linea = Mascota.to_linea(m)

      assert linea =~ "perro;;"
      assert {:ok, %Mascota{nombre: nil}} = Mascota.de_linea(linea)
    end

    test "de_linea rechaza una línea con campos de menos o de más" do
      assert {:error, :linea_invalida} = Mascota.de_linea("M001;perdida;perro")

      assert {:error, :linea_invalida} =
               Mascota.de_linea("M001;perdida;perro;Luna;;negra;mediano;centro;300;activa;extra")
    end

    test "de_linea rechaza tipo, tamaño o estado inválidos" do
      assert {:error, :tipo_invalido} =
               Mascota.de_linea("M001;robada;perro;Luna;;negra;mediano;centro;300;activa")

      assert {:error, :tamano_invalido} =
               Mascota.de_linea("M001;perdida;perro;Luna;;negra;enorme;centro;300;activa")

      assert {:error, :estado_invalido} =
               Mascota.de_linea("M001;perdida;perro;Luna;;negra;mediano;centro;300;cerrada")
    end

    test "de_linea aplica las validaciones de crear" do
      assert {:error, :especie_vacia} =
               Mascota.de_linea("M001;perdida;;Luna;;negra;mediano;centro;300;activa")
    end

    test "de_linea rechaza algo que no es texto" do
      assert {:error, :linea_invalida} = Mascota.de_linea(nil)
    end

    @tag :tmp_dir
    test "escribe y lee mascotas.csv con Emergencias.CSV", %{tmp_dir: tmp_dir} do
      ruta = Path.join(tmp_dir, Mascota.archivo())

      mascotas = [
        Fabrica.mascota(),
        Fabrica.mascota(
          id: "M002",
          tipo: :encontrada,
          nombre: nil,
          caracteristicas: "cola corta",
          tamano: :grande,
          estado: :posible_coincidencia
        )
      ]

      assert :ok = CSV.escribir(ruta, Mascota.cabecera(), mascotas, &Mascota.to_linea/1)
      assert {:ok, ^mascotas} = CSV.leer(ruta, &Mascota.de_linea/1)
    end

    @tag :tmp_dir
    test "una línea corrupta en el archivo se reporta con su número", %{tmp_dir: tmp_dir} do
      ruta = Path.join(tmp_dir, Mascota.archivo())

      contenido =
        Mascota.cabecera() <> "\n" <> Mascota.to_linea(Fabrica.mascota()) <> "\nbasura\n"

      assert :ok = File.write(ruta, contenido)

      assert {:error, {:linea_invalida, 3}} = CSV.leer(ruta, &Mascota.de_linea/1)
    end
  end
end
