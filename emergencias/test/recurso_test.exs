defmodule Emergencias.Dominio.RecursoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Recurso
  alias Emergencias.Fabrica

  describe "crear/7" do
    test "crea un recurso válido" do
      assert {:ok, recurso} =
               Recurso.crear("R001", "agua", :agua, 50, "litros", "centro_acopio_1", "centro")

      assert recurso == Fabrica.recurso()
    end

    test "acepta cantidad 0" do
      assert {:ok, %Recurso{cantidad_disponible: 0}} =
               Recurso.crear("R001", "agua", :agua, 0, "litros", "centro_acopio_1", "centro")
    end

    test "sanitiza los textos" do
      assert {:ok, recurso} =
               Recurso.crear("R001", " agua;potable ", :agua, 1, "litros", "acopio", "centro")

      assert recurso.nombre == "agua potable"
    end

    test "rechaza categoría inválida" do
      assert {:error, :categoria_invalida} =
               Recurso.crear("R001", "agua", :comida, 50, "litros", "acopio", "centro")

      assert {:error, :categoria_invalida} =
               Recurso.crear("R001", "agua", "agua", 50, "litros", "acopio", "centro")
    end

    test "rechaza cantidad negativa o no entera" do
      assert {:error, :cantidad_invalida} =
               Recurso.crear("R001", "agua", :agua, -1, "litros", "acopio", "centro")

      assert {:error, :cantidad_invalida} =
               Recurso.crear("R001", "agua", :agua, 2.5, "litros", "acopio", "centro")

      assert {:error, :cantidad_invalida} =
               Recurso.crear("R001", "agua", :agua, "5", "litros", "acopio", "centro")
    end

    test "rechaza cada texto vacío" do
      assert {:error, :texto_vacio} =
               Recurso.crear("", "agua", :agua, 5, "litros", "acopio", "centro")

      assert {:error, :texto_vacio} =
               Recurso.crear("R001", "  ", :agua, 5, "litros", "acopio", "centro")

      assert {:error, :texto_vacio} =
               Recurso.crear("R001", "agua", :agua, 5, "", "acopio", "centro")

      assert {:error, :texto_vacio} =
               Recurso.crear("R001", "agua", :agua, 5, "litros", nil, "centro")

      assert {:error, :texto_vacio} =
               Recurso.crear("R001", "agua", :agua, 5, "litros", "acopio", "")
    end
  end

  describe "entrada/2" do
    test "suma a la cantidad disponible" do
      assert {:ok, %Recurso{cantidad_disponible: 60}} = Recurso.entrada(Fabrica.recurso(), 10)
    end

    test "no modifica el recurso original" do
      original = Fabrica.recurso()
      {:ok, _nuevo} = Recurso.entrada(original, 10)
      assert original.cantidad_disponible == 50
    end

    test "rechaza cantidad 0, negativa o no entera" do
      recurso = Fabrica.recurso()
      assert {:error, :cantidad_invalida} = Recurso.entrada(recurso, 0)
      assert {:error, :cantidad_invalida} = Recurso.entrada(recurso, -5)
      assert {:error, :cantidad_invalida} = Recurso.entrada(recurso, 1.5)
      assert {:error, :cantidad_invalida} = Recurso.entrada(recurso, "5")
    end
  end

  describe "salida/2" do
    test "resta de la cantidad disponible" do
      assert {:ok, %Recurso{cantidad_disponible: 40}} = Recurso.salida(Fabrica.recurso(), 10)
    end

    test "permite dejar el stock en 0" do
      assert {:ok, %Recurso{cantidad_disponible: 0}} = Recurso.salida(Fabrica.recurso(), 50)
    end

    test "rechaza cantidad 0, negativa o no entera" do
      recurso = Fabrica.recurso()
      assert {:error, :cantidad_invalida} = Recurso.salida(recurso, 0)
      assert {:error, :cantidad_invalida} = Recurso.salida(recurso, -5)
      assert {:error, :cantidad_invalida} = Recurso.salida(recurso, 1.5)
    end

    test "rechaza una salida mayor que lo disponible" do
      recurso = Fabrica.recurso()
      assert {:error, :sin_stock} = Recurso.salida(recurso, 51)
      assert recurso.cantidad_disponible == 50
    end
  end

  describe "CSV" do
    test "a_linea/1 sigue el orden de la cabecera" do
      assert Recurso.cabecera() == "id;nombre;categoria;cantidad;unidad;ubicacion;zona"
      linea = "R001;agua;agua;50;litros;centro_acopio_1;centro"
      assert Recurso.a_linea(Fabrica.recurso()) == linea
    end

    test "de_linea/1 lee una línea válida" do
      assert {:ok, recurso} = Recurso.de_linea("R001;agua;agua;50;litros;centro_acopio_1;centro")
      assert recurso == Fabrica.recurso()
    end

    test "a_linea/1 y de_linea/1 son inversas" do
      recurso = Fabrica.recurso(categoria: :primeros_auxilios, cantidad_disponible: 0)
      assert {:ok, ^recurso} = recurso |> Recurso.a_linea() |> Recurso.de_linea()
    end

    test "de_linea/1 rechaza líneas corruptas sin lanzar excepción" do
      assert {:error, _} = Recurso.de_linea("")
      assert {:error, :linea_invalida} = Recurso.de_linea("R001;agua;agua")
      assert {:error, _} = Recurso.de_linea("R001;agua;comida;50;litros;acopio;centro")
      assert {:error, _} = Recurso.de_linea("R001;agua;agua;abc;litros;acopio;centro")
      assert {:error, _} = Recurso.de_linea("R001;agua;agua;-5;litros;acopio;centro")
      assert {:error, _} = Recurso.de_linea("R001;;agua;5;litros;acopio;centro")
      assert {:error, :linea_invalida} = Recurso.de_linea(nil)
    end
  end
end
