defmodule Emergencias.CLI.ParserSesionTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Parser

  describe "connect" do
    test "válido" do
      assert {:ok, {:connect, ["laura", "1234", :coordinador, "centro"]}} =
               Parser.parsear("connect laura 1234 coordinador centro")
    end

    test "acepta el tipo administrador" do
      assert {:ok, {:connect, ["root", "x", :administrador, "centro"]}} =
               Parser.parsear("connect root x administrador centro")
    end

    test "tipo inválido" do
      assert {:error, {:valor_invalido, :tipo}} =
               Parser.parsear("connect laura 1234 jefe centro")
    end

    test "faltan argumentos" do
      assert {:error, {:argumentos, esperados: 4}} = Parser.parsear("connect laura 1234")
    end

    test "sobran argumentos" do
      assert {:error, {:argumentos, esperados: 4}} =
               Parser.parsear("connect laura 1234 coordinador centro extra")
    end
  end

  describe "disconnect, help y exit" do
    test "válidos, sin distinguir mayúsculas" do
      assert {:ok, {:disconnect, []}} = Parser.parsear("disconnect")
      assert {:ok, {:help, []}} = Parser.parsear("help")
      assert {:ok, {:exit, []}} = Parser.parsear("EXIT\r\n")
    end

    test "con argumentos de más" do
      assert {:error, {:argumentos, esperados: 0}} = Parser.parsear("disconnect ahora")
      assert {:error, {:argumentos, esperados: 0}} = Parser.parsear("help connect")
      assert {:error, {:argumentos, esperados: 0}} = Parser.parsear("exit ya")
    end
  end
end
