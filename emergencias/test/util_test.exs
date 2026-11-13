defmodule Emergencias.UtilTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Emergencias.Util

  doctest Emergencias.Util

  describe "parsear_entero/1" do
    test "acepta enteros válidos, con espacios y con signo" do
      assert {:ok, 12} = Util.parsear_entero("12")
      assert {:ok, 12} = Util.parsear_entero("  12  ")
      assert {:ok, -3} = Util.parsear_entero("-3")
      assert {:ok, 0} = Util.parsear_entero("0")
    end

    test "rechaza entradas inválidas sin lanzar excepciones" do
      for entrada <- ["12a", "", "   ", "abc", "3.5", "1 2", nil, 5, :agua] do
        assert {:error, :entero_invalido} = Util.parsear_entero(entrada)
      end
    end
  end

  describe "parsear_entero_no_negativo/1" do
    test "acepta cero y positivos" do
      assert {:ok, 0} = Util.parsear_entero_no_negativo("0")
      assert {:ok, 30} = Util.parsear_entero_no_negativo("30")
    end

    test "rechaza negativos y basura" do
      for entrada <- ["-3", "12a", "", nil] do
        assert {:error, :entero_invalido} = Util.parsear_entero_no_negativo(entrada)
      end
    end
  end

  describe "parsear_real/1" do
    test "acepta decimales y enteros" do
      assert {:ok, 3.5} = Util.parsear_real("3.5")
      assert {:ok, 3.0} = Util.parsear_real("3")
      assert {:ok, -0.5} = Util.parsear_real(" -0.5 ")
    end

    test "rechaza entradas inválidas" do
      for entrada <- ["abc", "", "3.5x", ".", nil, 4] do
        assert {:error, :real_invalido} = Util.parsear_real(entrada)
      end
    end
  end

  describe "parsear_enum/2" do
    @permitidos [:critica, :alta, :media, :baja]

    test "ignora mayúsculas y espacios" do
      assert {:ok, :critica} = Util.parsear_enum("critica", @permitidos)
      assert {:ok, :alta} = Util.parsear_enum("  ALTA ", @permitidos)
    end

    test "rechaza valores fuera de la lista" do
      for entrada <- ["hack", "", "critico", nil, 3] do
        assert {:error, :valor_invalido} = Util.parsear_enum(entrada, @permitidos)
      end
    end

    test "no crea átomos nuevos con la entrada del usuario" do
      texto = "atomo_que_no_existe_" <> Integer.to_string(System.unique_integer([:positive]))
      assert {:error, :valor_invalido} = Util.parsear_enum(texto, @permitidos)

      assert_raise ArgumentError, fn -> String.to_existing_atom(texto) end
    end
  end

  describe "sanitizar_texto/1" do
    test "reemplaza ; y saltos de línea por espacio" do
      assert "a b c d" = Util.sanitizar_texto("a;b\nc\r\nd")
    end

    test "quita espacios de los extremos" do
      assert "hola" = Util.sanitizar_texto("  hola \n")
    end

    test "nil u otros tipos dan cadena vacía" do
      assert "" = Util.sanitizar_texto(nil)
      assert "" = Util.sanitizar_texto(5)
    end
  end

  describe "vacio?/1 y ahora/0" do
    test "vacio?" do
      assert Util.vacio?(nil)
      assert Util.vacio?("")
      assert Util.vacio?("  \n ")
      refute Util.vacio?("agua")
    end

    test "ahora devuelve una fecha ISO 8601 válida" do
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(Util.ahora())
    end
  end

  describe "mostrar_mensaje/1" do
    test "imprime con salto de línea" do
      assert capture_io(fn -> Util.mostrar_mensaje("hola") end) == "hola\n"
    end
  end

  describe "ingresar/2" do
    test "devuelve el dato cuando es válido" do
      salida =
        capture_io([input: "42\n"], fn ->
          send(self(), {:resultado, Util.ingresar("Cantidad:", :entero)})
        end)

      assert_received {:resultado, {:ok, 42}}
      assert salida =~ "Cantidad:"
    end

    test "vuelve a pedir el dato mientras sea inválido" do
      salida =
        capture_io([input: "abc\n-x\n7\n"], fn ->
          send(self(), {:resultado, Util.ingresar("Cantidad:", :entero)})
        end)

      assert_received {:resultado, {:ok, 7}}
      assert salida =~ "Dato inválido"
    end

    test "texto: rechaza vacío y sanitiza" do
      capture_io([input: "\n  agua; potable \n"], fn ->
        send(self(), {:resultado, Util.ingresar("Nombre:", :texto)})
      end)

      assert_received {:resultado, {:ok, "agua  potable"}}
    end

    test "real y boolean" do
      capture_io([input: "2.5\n"], fn ->
        send(self(), {:real, Util.ingresar("Peso:", :real)})
      end)

      assert_received {:real, {:ok, 2.5}}

      capture_io([input: "quizas\nSI\n"], fn ->
        send(self(), {:si, Util.ingresar("¿Líder?", :boolean)})
      end)

      assert_received {:si, {:ok, true}}

      capture_io([input: "no\n"], fn ->
        send(self(), {:no, Util.ingresar("¿Líder?", :boolean)})
      end)

      assert_received {:no, {:ok, false}}
    end

    test "si la entrada se cierra devuelve {:error, :eof} sin quedarse en bucle" do
      capture_io([input: ""], fn ->
        send(self(), {:resultado, Util.ingresar("Cantidad:", :entero)})
      end)

      assert_received {:resultado, {:error, :eof}}
    end

    test "tipo no soportado" do
      assert {:error, :tipo_invalido} = Util.ingresar("x", :fecha)
    end
  end
end
