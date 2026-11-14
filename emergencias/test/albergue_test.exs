defmodule Emergencias.Dominio.AlbergueTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Fabrica

  # ---------------------------------------------------------------------------
  # crear/5
  # ---------------------------------------------------------------------------

  describe "crear/5" do
    test "crea un albergue válido sin personas registradas" do
      assert {:ok, albergue} = Albergue.crear("A01", "Albergue Norte", "centro", 100, 10)

      assert albergue.id == "A01"
      assert albergue.nombre == "Albergue Norte"
      assert albergue.zona == "centro"
      assert albergue.capacidad_maxima == 100
      assert albergue.ocupacion_actual == 10
      assert albergue.personas == MapSet.new()
    end

    test "acepta ocupación igual a la capacidad" do
      assert {:ok, albergue} = Albergue.crear("A01", "Albergue Norte", "centro", 50, 50)
      assert albergue.ocupacion_actual == 50
    end

    test "acepta capacidad 0 con ocupación 0" do
      assert {:ok, albergue} = Albergue.crear("A01", "Albergue Norte", "centro", 0, 0)
      assert albergue.capacidad_maxima == 0
    end

    test "sanitiza los textos (punto y coma, saltos de línea y espacios)" do
      assert {:ok, albergue} = Albergue.crear(" A01 ", "Albergue;\nNorte ", " centro ", 10, 0)

      assert albergue.id == "A01"
      assert albergue.nombre == "Albergue  Norte"
      assert albergue.zona == "centro"
    end

    test "rechaza id vacío o que no es texto" do
      assert {:error, :id_invalido} = Albergue.crear("  ", "Albergue", "centro", 10, 0)
      assert {:error, :id_invalido} = Albergue.crear(nil, "Albergue", "centro", 10, 0)
    end

    test "rechaza nombre vacío o que no es texto" do
      assert {:error, :nombre_invalido} = Albergue.crear("A01", "", "centro", 10, 0)
      assert {:error, :nombre_invalido} = Albergue.crear("A01", ";", "centro", 10, 0)
      assert {:error, :nombre_invalido} = Albergue.crear("A01", 123, "centro", 10, 0)
    end

    test "rechaza zona vacía o que no es texto" do
      assert {:error, :zona_invalida} = Albergue.crear("A01", "Albergue", "", 10, 0)
      assert {:error, :zona_invalida} = Albergue.crear("A01", "Albergue", nil, 10, 0)
    end

    test "rechaza capacidad negativa" do
      assert {:error, :capacidad_invalida} = Albergue.crear("A01", "Albergue", "centro", -1, 0)
    end

    test "rechaza capacidad que no es entera" do
      assert {:error, :capacidad_invalida} = Albergue.crear("A01", "Albergue", "centro", 10.5, 0)
      assert {:error, :capacidad_invalida} = Albergue.crear("A01", "Albergue", "centro", "10", 0)
    end

    test "rechaza ocupación negativa" do
      assert {:error, :ocupacion_invalida} = Albergue.crear("A01", "Albergue", "centro", 10, -1)
    end

    test "rechaza ocupación que no es entera" do
      assert {:error, :ocupacion_invalida} = Albergue.crear("A01", "Albergue", "centro", 10, 2.0)
      assert {:error, :ocupacion_invalida} = Albergue.crear("A01", "Albergue", "centro", 10, nil)
    end

    test "rechaza ocupación mayor que la capacidad" do
      assert {:error, :ocupacion_supera_capacidad} =
               Albergue.crear("A01", "Albergue", "centro", 10, 11)

      assert {:error, :ocupacion_supera_capacidad} =
               Albergue.crear("A01", "Albergue", "centro", 0, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # cupos_disponibles/1
  # ---------------------------------------------------------------------------

  describe "cupos_disponibles/1" do
    test "es la capacidad menos la ocupación" do
      albergue = Fabrica.albergue(capacidad_maxima: 100, ocupacion_actual: 30)
      assert Albergue.cupos_disponibles(albergue) == 70
    end

    test "es 0 cuando el albergue está lleno" do
      albergue = Fabrica.albergue(capacidad_maxima: 5, ocupacion_actual: 5)
      assert Albergue.cupos_disponibles(albergue) == 0
    end

    test "es 0 con capacidad 0" do
      albergue = Fabrica.albergue(capacidad_maxima: 0, ocupacion_actual: 0)
      assert Albergue.cupos_disponibles(albergue) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # registrar_ingreso/2
  # ---------------------------------------------------------------------------

  describe "registrar_ingreso/2" do
    test "con cupo: suma 1 a la ocupación y agrega el documento" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 3)

      assert {:ok, nuevo} = Albergue.registrar_ingreso(albergue, "1094")
      assert nuevo.ocupacion_actual == 4
      assert MapSet.member?(nuevo.personas, "1094")
    end

    test "no modifica la struct original" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)

      assert {:ok, _nuevo} = Albergue.registrar_ingreso(albergue, "1094")
      assert albergue.ocupacion_actual == 0
      assert albergue.personas == MapSet.new()
    end

    test "ocupa el último cupo y luego rechaza por falta de cupo" do
      albergue = Fabrica.albergue(capacidad_maxima: 1, ocupacion_actual: 0)

      assert {:ok, lleno} = Albergue.registrar_ingreso(albergue, "1094")
      assert Albergue.cupos_disponibles(lleno) == 0
      assert {:error, :sin_cupo} = Albergue.registrar_ingreso(lleno, "2020")
    end

    test "sin cupo: devuelve :sin_cupo" do
      albergue = Fabrica.albergue(capacidad_maxima: 2, ocupacion_actual: 2)
      assert {:error, :sin_cupo} = Albergue.registrar_ingreso(albergue, "1094")
    end

    test "capacidad 0: devuelve :sin_cupo" do
      albergue = Fabrica.albergue(capacidad_maxima: 0, ocupacion_actual: 0)
      assert {:error, :sin_cupo} = Albergue.registrar_ingreso(albergue, "1094")
    end

    test "documento duplicado: devuelve :ya_registrado" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)

      assert {:ok, con_persona} = Albergue.registrar_ingreso(albergue, "1094")
      assert {:error, :ya_registrado} = Albergue.registrar_ingreso(con_persona, "1094")
    end

    test "documento duplicado con espacios alrededor: devuelve :ya_registrado" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)

      assert {:ok, con_persona} = Albergue.registrar_ingreso(albergue, "1094")
      assert {:error, :ya_registrado} = Albergue.registrar_ingreso(con_persona, " 1094 ")
    end

    test "lleno y con el documento ya registrado: gana :sin_cupo" do
      albergue =
        Fabrica.albergue(
          capacidad_maxima: 1,
          ocupacion_actual: 1,
          personas: MapSet.new(["1094"])
        )

      assert {:error, :sin_cupo} = Albergue.registrar_ingreso(albergue, "1094")
    end

    test "documento vacío o que no es texto: devuelve :documento_invalido" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)

      assert {:error, :documento_invalido} = Albergue.registrar_ingreso(albergue, "   ")
      assert {:error, :documento_invalido} = Albergue.registrar_ingreso(albergue, nil)
      assert {:error, :documento_invalido} = Albergue.registrar_ingreso(albergue, 1094)
    end
  end

  # ---------------------------------------------------------------------------
  # registrar_salida/2
  # ---------------------------------------------------------------------------

  describe "registrar_salida/2" do
    test "persona presente: resta 1 a la ocupación y quita el documento" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)
      {:ok, con_persona} = Albergue.registrar_ingreso(albergue, "1094")

      assert {:ok, nuevo} = Albergue.registrar_salida(con_persona, "1094")
      assert nuevo.ocupacion_actual == 0
      refute MapSet.member?(nuevo.personas, "1094")
    end

    test "la persona puede volver a ingresar después de salir" do
      albergue = Fabrica.albergue(capacidad_maxima: 1, ocupacion_actual: 0)
      {:ok, con_persona} = Albergue.registrar_ingreso(albergue, "1094")
      {:ok, vacio} = Albergue.registrar_salida(con_persona, "1094")

      assert {:ok, de_nuevo} = Albergue.registrar_ingreso(vacio, "1094")
      assert de_nuevo.ocupacion_actual == 1
    end

    test "salida de quien no está: devuelve :persona_no_esta" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)
      assert {:error, :persona_no_esta} = Albergue.registrar_salida(albergue, "1094")
    end

    test "segunda salida de la misma persona: devuelve :persona_no_esta" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)
      {:ok, con_persona} = Albergue.registrar_ingreso(albergue, "1094")
      {:ok, sin_persona} = Albergue.registrar_salida(con_persona, "1094")

      assert {:error, :persona_no_esta} = Albergue.registrar_salida(sin_persona, "1094")
    end

    test "ocupación inicial sin documento: la salida por documento no aplica" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 4)
      assert {:error, :persona_no_esta} = Albergue.registrar_salida(albergue, "1094")
    end

    test "documento vacío o que no es texto: devuelve :documento_invalido" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 0)

      assert {:error, :documento_invalido} = Albergue.registrar_salida(albergue, "")
      assert {:error, :documento_invalido} = Albergue.registrar_salida(albergue, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # porcentaje_ocupacion/1
  # ---------------------------------------------------------------------------

  describe "porcentaje_ocupacion/1" do
    test "vacío es 0.0" do
      albergue = Fabrica.albergue(capacidad_maxima: 100, ocupacion_actual: 0)
      assert Albergue.porcentaje_ocupacion(albergue) == 0.0
    end

    test "ocupación parcial" do
      albergue = Fabrica.albergue(capacidad_maxima: 200, ocupacion_actual: 50)
      assert Albergue.porcentaje_ocupacion(albergue) == 25.0
    end

    test "lleno es 100.0" do
      albergue = Fabrica.albergue(capacidad_maxima: 40, ocupacion_actual: 40)
      assert Albergue.porcentaje_ocupacion(albergue) == 100.0
    end

    test "no redondea" do
      albergue = Fabrica.albergue(capacidad_maxima: 3, ocupacion_actual: 1)
      assert_in_delta Albergue.porcentaje_ocupacion(albergue), 33.333, 0.001
    end

    test "capacidad 0 devuelve 0.0 sin dividir por cero" do
      albergue = Fabrica.albergue(capacidad_maxima: 0, ocupacion_actual: 0)
      resultado = Albergue.porcentaje_ocupacion(albergue)

      assert resultado == 0.0
      assert is_float(resultado)
    end

    test "siempre devuelve un decimal" do
      albergue = Fabrica.albergue(capacidad_maxima: 10, ocupacion_actual: 5)
      assert is_float(Albergue.porcentaje_ocupacion(albergue))
    end
  end
end
