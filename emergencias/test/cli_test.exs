defmodule Emergencias.CLITest do
  use ExUnit.Case, async: false

  setup_all do
    estaba_arriba? =
      Enum.any?(Application.started_applications(), fn {app, _, _} -> app == :emergencias end)

    {:ok, _} = Application.ensure_all_started(:emergencias)

    # Deja todo como lo encontró: si la app estaba detenida, la detiene al terminar.
    unless estaba_arriba?, do: on_exit(fn -> Application.stop(:emergencias) end)

    :ok
  end

  import ExUnit.CaptureIO

  alias Emergencias.CLI
  alias Emergencias.CLI.Formato
  alias Emergencias.Dominio.Usuario

  defp nombre_unico, do: "cli_#{System.unique_integer([:positive])}"

  defp correr(entrada), do: capture_io(entrada, fn -> CLI.iniciar() end)

  defp conectar(nombre, tipo \\ "coordinador"), do: "connect #{nombre} 1234 #{tipo} centro\n"

  describe "iniciar/0" do
    test "exit termina la consola" do
      salida = correr("exit\n")

      assert salida =~ Formato.bienvenida()
      assert salida =~ Formato.despedida()
    end

    test "el fin de la entrada (:eof) termina la consola" do
      assert correr("") =~ Formato.despedida()
    end

    test "conectar, ver help y salir desconecta al usuario" do
      nombre = nombre_unico()
      salida = correr(conectar(nombre) <> "help\nexit\n")

      assert salida =~ "Sesión iniciada: Usuario #{nombre}"
      assert salida =~ "Comandos disponibles para coordinador:"
      assert salida =~ "register_zone codigo nombre nivel"
      assert salida =~ Formato.sesion_cerrada()
      assert salida =~ Formato.despedida()
    end

    test "al salir con exit el usuario queda desconectado y puede volver a conectarse" do
      nombre = nombre_unico()
      _ = correr(conectar(nombre) <> "exit\n")
      salida = correr(conectar(nombre) <> "exit\n")

      assert salida =~ "Sesión iniciada: Usuario #{nombre}"
    end

    test "la entrada basura muestra errores y la consola sigue" do
      salida = correr("asdf\n\n   \nhelp extra\nhelp\nexit\n")

      assert salida =~ Formato.a_texto({:error, :comando_desconocido})
      assert salida =~ Formato.a_texto({:error, :linea_vacia})
      assert salida =~ Formato.a_texto({:error, {:argumentos, esperados: 0}})
      # Llegó hasta el help y hasta el exit.
      assert salida =~ "Comandos disponibles"
      assert salida =~ Formato.despedida()
    end

    test "sin sesión, un comando válido da :no_conectado" do
      salida = correr("list_needs\nexit\n")

      assert salida =~ Formato.a_texto({:error, :no_conectado})
    end

    test "sin sesión, disconnect da :no_conectado" do
      salida = correr("disconnect\nexit\n")

      assert salida =~ Formato.a_texto({:error, :no_conectado})
    end

    test "sin sesión, help solo muestra connect, help y exit" do
      salida = correr("help\nexit\n")

      assert salida =~ "connect usuario contrasena tipo zona"
      refute salida =~ "register_zone"
      refute salida =~ "summary"
    end

    test "connect con argumentos de más o con tipo inválido muestra error" do
      salida = correr("connect a 1 coordinador centro extra\nconnect a 1 jefe centro\nexit\n")

      assert salida =~ Formato.a_texto({:error, {:argumentos, esperados: 4}})
      assert salida =~ Formato.a_texto({:error, {:valor_invalido, :tipo}})
    end

    test "connect con contraseña incorrecta no abre sesión" do
      nombre = nombre_unico()

      salida =
        correr(
          conectar(nombre) <>
            "disconnect\n" <>
            "connect #{nombre} otra coordinador centro\n" <>
            "list_needs\nexit\n"
        )

      assert salida =~ Formato.a_texto({:error, :credenciales_invalidas})
      assert salida =~ Formato.a_texto({:error, :no_conectado})
    end

    test "connect estando conectado da :ya_conectado" do
      nombre = nombre_unico()
      salida = correr(conectar(nombre) <> conectar(nombre) <> "exit\n")

      assert salida =~ Formato.a_texto({:error, :ya_conectado})
    end

    test "disconnect deja la sesión en nil" do
      nombre = nombre_unico()
      salida = correr(conectar(nombre) <> "disconnect\nlist_needs\nexit\n")

      assert salida =~ Formato.sesion_cerrada()
      assert salida =~ Formato.a_texto({:error, :no_conectado})
    end

    test "help depende del rol de la sesión" do
      nombre = nombre_unico()
      salida = correr(conectar(nombre, "ciudadano") <> "help\nexit\n")

      assert salida =~ "Comandos disponibles para ciudadano:"
      assert salida =~ "register_need"
      refute salida =~ "register_zone"
    end
  end

  describe "procesar/2" do
    test "devuelve {:salir, texto} con exit y sin sesión" do
      assert {:salir, texto} = CLI.procesar(nil, "exit")
      assert texto == Formato.despedida()
    end

    test "una línea vacía deja la sesión igual y muestra un error" do
      assert {:continuar, nil, texto} = CLI.procesar(nil, "   \n")
      assert texto == Formato.a_texto({:error, :linea_vacia})
    end

    test "con sesión, un comando que falla no cambia la sesión" do
      {:ok, usuario} = Usuario.crear("ana", "1234", "Ana", :ciudadano, "centro")
      sesion = Usuario.conectar(usuario)

      assert {:continuar, ^sesion, texto} = CLI.procesar(sesion, "asdf")
      assert texto == Formato.a_texto({:error, :comando_desconocido})
    end

    test "bytes inválidos no tumban la consola" do
      assert {:continuar, nil, texto} = CLI.procesar(nil, <<255, 254, 10>>)
      assert is_binary(texto)
    end
  end
end
