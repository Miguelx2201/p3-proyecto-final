defmodule Emergencias.CLI.ComandosTest do
  # Los servidores tienen nombre fijo y comparten `data_dir`: no puede ser async.
  use ExUnit.Case, async: false

  alias Emergencias.CLI.Comandos
  alias Emergencias.CLI.Formato
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Dominio.Zona
  alias Emergencias.Fabrica
  alias Emergencias.Procesos.AlberguesSupervisor
  alias Emergencias.Procesos.MascotasServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.Procesos.RegistroActividad
  alias Emergencias.Procesos.UsuariosServer
  alias Emergencias.Procesos.ZonasServer

  # `mix test` corre con `--no-start`: cada prueba arranca el árbol completo
  # con su propia carpeta de datos.
  setup do
    ruta =
      Path.join(
        System.tmp_dir() || ".",
        "emergencias_comandos_#{System.unique_integer([:positive])}"
      )

    :ok = File.mkdir_p(ruta)
    anterior = Application.get_env(:emergencias, :data_dir)
    Application.put_env(:emergencias, :data_dir, ruta)

    on_exit(fn ->
      if anterior,
        do: Application.put_env(:emergencias, :data_dir, anterior),
        else: Application.delete_env(:emergencias, :data_dir)

      File.rm_rf(ruta)
    end)

    iniciar({Registry, keys: :unique, name: Emergencias.Registry})

    Enum.each(
      [
        RegistroActividad,
        UsuariosServer,
        ZonasServer,
        NecesidadesServer,
        RecursosServer,
        PersonasServer,
        MascotasServer,
        AlberguesSupervisor
      ],
      &iniciar/1
    )

    %{
      coordinador: Fabrica.usuario(username: "laura", tipo: :coordinador),
      voluntario: Fabrica.usuario(username: "vera", tipo: :voluntario),
      ciudadano: Fabrica.usuario(username: "carlos", tipo: :ciudadano)
    }
  end

  defp iniciar(especificacion) do
    assert {:ok, _pid} = start_supervised(especificacion)
    :ok
  end

  defp zona_centro(coordinador) do
    assert {:ok, %Zona{}} =
             Comandos.ejecutar(coordinador, :register_zone, ["centro", "Zona Centro", :critico])

    :ok
  end

  defp sector_s1(coordinador) do
    assert {:ok, _zona} =
             Comandos.ejecutar(coordinador, :register_sector, ["centro", "S1", "Sector 1", 200])

    :ok
  end

  # ---------------------------------------------------------------------------
  # connect y disconnect
  # ---------------------------------------------------------------------------

  describe "connect" do
    test "válido: registra y conecta al usuario" do
      assert {:ok, %Usuario{username: "laura", tipo: :coordinador, conectado: true}} =
               Comandos.ejecutar(nil, :connect, ["laura", "1234", :coordinador, "centro"])
    end

    test "inválido: contraseña incorrecta" do
      assert {:ok, _usuario} =
               Comandos.ejecutar(nil, :connect, ["laura", "1234", :coordinador, "centro"])

      assert {:error, :credenciales_invalidas} =
               Comandos.ejecutar(nil, :connect, ["laura", "otra", :coordinador, "centro"])
    end

    test "inválido: tipo de usuario" do
      assert {:error, :tipo_invalido} =
               Comandos.ejecutar(nil, :connect, ["laura", "1234", :rey, "centro"])
    end

    test "inválido: ya hay una sesión", %{coordinador: c} do
      assert {:error, :ya_conectado} =
               Comandos.ejecutar(c, :connect, ["laura", "1234", :coordinador, "centro"])
    end

    test "inválido: cantidad de argumentos" do
      assert {:error, {:argumentos, esperados: 4}} =
               Comandos.ejecutar(nil, :connect, ["laura", "1234"])
    end
  end

  describe "disconnect" do
    test "válido, y una segunda vez da :no_conectado" do
      assert {:ok, usuario} =
               Comandos.ejecutar(nil, :connect, ["ana", "1234", :voluntario, "centro"])

      assert :ok = Comandos.ejecutar(usuario, :disconnect, [])
      assert {:error, :no_conectado} = Comandos.ejecutar(usuario, :disconnect, [])
    end

    test "inválido: no recibe argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 0}} = Comandos.ejecutar(c, :disconnect, ["x"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :disconnect, [])
    end
  end

  # ---------------------------------------------------------------------------
  # Zonas
  # ---------------------------------------------------------------------------

  describe "register_zone" do
    test "válido", %{coordinador: c} do
      assert {:ok, %Zona{codigo: "centro", nombre: "Zona Centro", nivel: :critico}} =
               Comandos.ejecutar(c, :register_zone, ["centro", "Zona Centro", :critico])
    end

    test "inválido: zona repetida", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :id_duplicado} =
               Comandos.ejecutar(c, :register_zone, ["centro", "Otra", :alto])
    end

    test "inválido: nivel", %{coordinador: c} do
      assert {:error, :nivel_invalido} =
               Comandos.ejecutar(c, :register_zone, ["norte", "Norte", :enorme])
    end

    test "inválido: permiso", %{voluntario: voluntario} do
      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(voluntario, :register_zone, ["norte", "Norte", :alto])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 3}} =
               Comandos.ejecutar(c, :register_zone, ["centro"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :register_zone, ["centro", "Zona Centro", :critico])
    end
  end

  describe "register_sector" do
    test "válido", %{coordinador: c} do
      zona_centro(c)

      assert {:ok, %Zona{codigo: "centro"}} =
               Comandos.ejecutar(c, :register_sector, ["centro", "S1", "Sector 1", 200])
    end

    test "inválido: zona inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} =
               Comandos.ejecutar(c, :register_sector, ["nada", "S1", "Sector 1", 10])
    end

    test "inválido: cantidad de personas", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :cantidad_invalida} =
               Comandos.ejecutar(c, :register_sector, ["centro", "S1", "Sector 1", -1])
    end

    test "inválido: permiso", %{coordinador: c, voluntario: voluntario} do
      zona_centro(c)

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(voluntario, :register_sector, ["centro", "S1", "S", 1])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 4}} =
               Comandos.ejecutar(c, :register_sector, ["centro", "S1"])
    end
  end

  describe "register_point" do
    test "válido", %{coordinador: c} do
      zona_centro(c)
      sector_s1(c)

      assert {:ok, %Zona{codigo: "centro"}} =
               Comandos.ejecutar(c, :register_point, ["centro", "S1", "P1", "Punto 3", 40])
    end

    test "inválido: zona inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} =
               Comandos.ejecutar(c, :register_point, ["nada", "S1", "P1", "Punto", 10])
    end

    test "inválido: permiso", %{coordinador: c, voluntario: voluntario} do
      zona_centro(c)
      sector_s1(c)

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(voluntario, :register_point, ["centro", "S1", "P1", "P", 1])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 5}} =
               Comandos.ejecutar(c, :register_point, ["centro", "S1", "P1"])
    end
  end

  describe "zone_status" do
    test "válido: cualquier tipo de usuario", %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)

      assert {:ok, %Zona{codigo: "centro", nombre: "Zona Centro"}} =
               Comandos.ejecutar(ciudadano, :zone_status, ["centro"])
    end

    test "inválido: zona inexistente", %{ciudadano: ciudadano} do
      assert {:error, :no_encontrado} = Comandos.ejecutar(ciudadano, :zone_status, ["nada"])
    end

    test "inválido: cantidad de argumentos", %{ciudadano: ciudadano} do
      assert {:error, {:argumentos, esperados: 1}} =
               Comandos.ejecutar(ciudadano, :zone_status, [])
    end
  end

  describe "zone_stats" do
    test "válido", %{coordinador: c} do
      zona_centro(c)
      sector_s1(c)

      assert {:ok, %{por_sector: [%{codigo: "S1"}]}} =
               Comandos.ejecutar(c, :zone_stats, ["centro"])
    end

    test "inválido: zona inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} = Comandos.ejecutar(c, :zone_stats, ["nada"])
    end

    test "inválido: permiso", %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      assert {:error, :permiso_denegado} = Comandos.ejecutar(ciudadano, :zone_stats, ["centro"])
    end
  end

  # ---------------------------------------------------------------------------
  # Otros
  # ---------------------------------------------------------------------------

  describe "otros casos" do
    test "comando que aún no tiene cláusula", %{coordinador: c} do
      assert {:error, :no_implementado} = Comandos.ejecutar(c, :pending_needs, [])
    end

    test "argumentos que no son una lista", %{coordinador: c} do
      assert {:error, :valor_invalido} = Comandos.ejecutar(c, :zone_status, "centro")
    end

    test "sesión que no es un Usuario", %{coordinador: _c} do
      assert {:error, :usuario_invalido} = Comandos.ejecutar(%{tipo: :coordinador}, :zone_status, ["a"])
    end
  end

  describe "errores en español (criterio de aceptación)" do
    test "zona repetida, nivel inválido y permiso se muestran en español", %{
      coordinador: c,
      voluntario: voluntario
    } do
      zona_centro(c)

      repetida = Comandos.ejecutar(c, :register_zone, ["centro", "Otra", :alto])
      nivel = Comandos.ejecutar(c, :register_zone, ["norte", "Norte", :enorme])
      permiso = Comandos.ejecutar(voluntario, :register_zone, ["sur", "Sur", :alto])

      assert Formato.a_texto(repetida) == "Ya existe un registro con ese identificador."

      assert Formato.a_texto(nivel) ==
               "El nivel no es válido (critico, alto, medio o bajo)."

      assert Formato.a_texto(permiso) ==
               "Su tipo de usuario no tiene permiso para ejecutar ese comando."
    end
  end
end
