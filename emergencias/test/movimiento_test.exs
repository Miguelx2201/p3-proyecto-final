defmodule Emergencias.Dominio.MovimientoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Movimiento
  alias Emergencias.Fabrica

  describe "nuevo/5" do
    test "crea un movimiento válido con fecha actual e id nil" do
      assert {:ok, movimiento} = Movimiento.nuevo("R001", :asignacion, 5, "laura", "N001")

      assert movimiento.id == nil
      assert movimiento.recurso_id == "R001"
      assert movimiento.tipo == :asignacion
      assert movimiento.cantidad == 5
      assert movimiento.usuario == "laura"
      assert movimiento.referencia == "N001"
      assert {:ok, _fecha, _desfase} = DateTime.from_iso8601(movimiento.fecha)
    end

    test "acepta todos los tipos válidos" do
      for tipo <- Movimiento.tipos() do
        assert {:ok, %Movimiento{tipo: ^tipo}} = Movimiento.nuevo("R001", tipo, 1, "laura", nil)
      end
    end

    test "acepta referencia nil y convierte el texto vacío en nil" do
      assert {:ok, %Movimiento{referencia: nil}} = Movimiento.nuevo("R001", :entrada, 1, "l", nil)
      assert {:ok, %Movimiento{referencia: nil}} = Movimiento.nuevo("R001", :entrada, 1, "l", " ")
    end

    test "rechaza tipo inválido" do
      assert {:error, :tipo_invalido} = Movimiento.nuevo("R001", :robo, 5, "laura", nil)
      assert {:error, :tipo_invalido} = Movimiento.nuevo("R001", "entrada", 5, "laura", nil)
    end

    test "rechaza cantidad 0, negativa o no entera" do
      assert {:error, :cantidad_invalida} = Movimiento.nuevo("R001", :entrada, 0, "laura", nil)
      assert {:error, :cantidad_invalida} = Movimiento.nuevo("R001", :entrada, -1, "laura", nil)
      assert {:error, :cantidad_invalida} = Movimiento.nuevo("R001", :entrada, 1.5, "laura", nil)
    end

    test "rechaza recurso_id o usuario vacíos" do
      assert {:error, :texto_vacio} = Movimiento.nuevo("", :entrada, 5, "laura", nil)
      assert {:error, :texto_vacio} = Movimiento.nuevo("R001", :entrada, 5, " ", nil)
      assert {:error, :texto_vacio} = Movimiento.nuevo("R001", :entrada, 5, nil, nil)
    end

    test "rechaza referencia que no es texto ni nil" do
      assert {:error, :referencia_invalida} = Movimiento.nuevo("R001", :entrada, 5, "laura", 123)
    end
  end

  describe "CSV" do
    test "a_linea/1 sigue el orden de la cabecera" do
      assert Movimiento.cabecera() == "id;recurso_id;tipo;cantidad;fecha;usuario;referencia"

      assert Movimiento.a_linea(Fabrica.movimiento(referencia: "N001")) ==
               "MV001;R001;entrada;10;2026-01-01T00:00:00Z;laura;N001"
    end

    test "a_linea/1 escribe la referencia nil como campo vacío" do
      assert Movimiento.a_linea(Fabrica.movimiento()) ==
               "MV001;R001;entrada;10;2026-01-01T00:00:00Z;laura;"
    end

    test "de_linea/1 lee una línea válida" do
      linea = "MV001;R001;transferencia_salida;10;2026-01-01T00:00:00Z;laura;centro_2"
      assert {:ok, movimiento} = Movimiento.de_linea(linea)

      assert movimiento ==
               Fabrica.movimiento(tipo: :transferencia_salida, referencia: "centro_2")
    end

    test "de_linea/1 lee la referencia vacía como nil" do
      assert {:ok, %Movimiento{referencia: nil}} =
               Movimiento.de_linea("MV001;R001;entrada;10;2026-01-01T00:00:00Z;laura;")
    end

    test "a_linea/1 y de_linea/1 son inversas" do
      movimiento = Fabrica.movimiento(tipo: :asignacion, referencia: "N007")
      assert {:ok, ^movimiento} = movimiento |> Movimiento.a_linea() |> Movimiento.de_linea()
    end

    test "de_linea/1 rechaza líneas corruptas sin lanzar excepción" do
      assert {:error, :linea_invalida} = Movimiento.de_linea("")
      assert {:error, :linea_invalida} = Movimiento.de_linea("MV001;R001;entrada")
      assert {:error, _} = Movimiento.de_linea("MV001;R001;robo;10;2026-01-01T00:00:00Z;laura;")

      assert {:error, _} =
               Movimiento.de_linea("MV001;R001;entrada;abc;2026-01-01T00:00:00Z;laura;")

      assert {:error, _} = Movimiento.de_linea("MV001;R001;entrada;0;2026-01-01T00:00:00Z;laura;")
      assert {:error, :fecha_invalida} = Movimiento.de_linea("MV001;R001;entrada;10;ayer;laura;")

      assert {:error, :texto_vacio} =
               Movimiento.de_linea(";R001;entrada;10;2026-01-01T00:00:00Z;laura;")

      assert {:error, :linea_invalida} = Movimiento.de_linea(nil)
    end
  end
end
