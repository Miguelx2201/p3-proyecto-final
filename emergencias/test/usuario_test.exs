defmodule Emergencias.UsuarioTest do
  use ExUnit.Case, async: true

  alias Emergencias.CSV
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Fabrica

  @hash_1234 "03AC674216F3E15C761EE1A5E255F067953623C8B388B4459E13F978D7C846F4"

  describe "crear/5" do
    test "crea un usuario válido con hash y sin conexión" do
      assert {:ok, usuario} =
               Usuario.crear("laura", "1234", "Laura Gómez", :coordinador, "centro")

      assert usuario.username == "laura"
      assert usuario.nombre_completo == "Laura Gómez"
      assert usuario.tipo == :coordinador
      assert usuario.zona == "centro"
      assert usuario.conectado == false
      assert usuario.password_hash == @hash_1234
      refute usuario.password_hash == "1234"
    end

    test "acepta los 4 tipos de usuario" do
      for tipo <- [:ciudadano, :voluntario, :coordinador, :administrador] do
        assert {:ok, %Usuario{tipo: ^tipo}} = Usuario.crear("u", "p", "Nombre", tipo, "z")
      end
    end

    test "rechaza username vacío" do
      assert {:error, :campo_vacio} = Usuario.crear("", "1234", "Laura", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear("   ", "1234", "Laura", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear(nil, "1234", "Laura", :ciudadano, "centro")
    end

    test "rechaza password vacío" do
      assert {:error, :campo_vacio} = Usuario.crear("laura", "", "Laura", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear("laura", "  ", "Laura", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear("laura", nil, "Laura", :ciudadano, "centro")
    end

    test "rechaza nombre_completo vacío" do
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", "", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", "  ", :ciudadano, "centro")
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", nil, :ciudadano, "centro")
    end

    test "rechaza zona vacía" do
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", "Laura", :ciudadano, "")
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", "Laura", :ciudadano, "  ")
      assert {:error, :campo_vacio} = Usuario.crear("laura", "1234", "Laura", :ciudadano, nil)
    end

    test "un texto que solo tiene punto y coma queda vacío tras sanitizar" do
      assert {:error, :campo_vacio} = Usuario.crear(";", "1234", "Laura", :ciudadano, "centro")
    end

    test "rechaza un tipo que no es uno de los 4 permitidos" do
      assert {:error, :tipo_invalido} = Usuario.crear("laura", "1234", "Laura", :otro, "centro")
      assert {:error, :tipo_invalido} = Usuario.crear("laura", "1234", "Laura", nil, "centro")

      # El tipo debe ser átomo: el texto "ciudadano" no vale.
      assert {:error, :tipo_invalido} =
               Usuario.crear("laura", "1234", "Laura", "ciudadano", "centro")
    end

    test "campo_vacio tiene prioridad sobre tipo_invalido" do
      assert {:error, :campo_vacio} = Usuario.crear("", "1234", "Laura", :otro, "centro")
    end

    test "sanitiza los textos libres para no romper el CSV" do
      assert {:ok, usuario} =
               Usuario.crear(" laura ", "1234", "Laura; Gómez\n", :ciudadano, "centro")

      assert usuario.username == "laura"
      assert usuario.nombre_completo == "Laura  Gómez"
      assert length(CSV.separar(Usuario.to_linea(usuario))) == 5
    end
  end

  describe "autenticar/2" do
    test "contraseña correcta devuelve el usuario" do
      usuario = Fabrica.usuario()
      assert {:ok, ^usuario} = Usuario.autenticar(usuario, Fabrica.contrasena())
    end

    test "contraseña incorrecta da credenciales_invalidas" do
      assert {:error, :credenciales_invalidas} = Usuario.autenticar(Fabrica.usuario(), "otra")
    end

    test "contraseña vacía o que no es texto da credenciales_invalidas" do
      usuario = Fabrica.usuario()
      assert {:error, :credenciales_invalidas} = Usuario.autenticar(usuario, "")
      assert {:error, :credenciales_invalidas} = Usuario.autenticar(usuario, nil)
      assert {:error, :credenciales_invalidas} = Usuario.autenticar(usuario, 1234)
    end

    test "no cambia el estado de conexión" do
      usuario = Fabrica.usuario()
      assert {:ok, %Usuario{conectado: false}} = Usuario.autenticar(usuario, Fabrica.contrasena())
    end

    test "funciona con un usuario creado con crear/5" do
      {:ok, usuario} = Usuario.crear("laura", "secreta", "Laura", :ciudadano, "centro")
      assert {:ok, ^usuario} = Usuario.autenticar(usuario, "secreta")
      assert {:error, :credenciales_invalidas} = Usuario.autenticar(usuario, "Secreta")
    end
  end

  describe "conectar/1 y desconectar/1" do
    test "conectar pasa de desconectado a conectado" do
      assert %Usuario{conectado: true} = Usuario.conectar(Fabrica.usuario(conectado: false))
    end

    test "desconectar pasa de conectado a desconectado" do
      assert %Usuario{conectado: false} = Usuario.desconectar(Fabrica.usuario(conectado: true))
    end

    test "conectar un usuario ya conectado lo deja igual (idempotente)" do
      usuario = Fabrica.usuario(conectado: true)
      assert Usuario.conectar(usuario) == usuario
    end

    test "desconectar un usuario ya desconectado lo deja igual (idempotente)" do
      usuario = Fabrica.usuario(conectado: false)
      assert Usuario.desconectar(usuario) == usuario
    end

    test "solo cambia el campo conectado" do
      usuario = Fabrica.usuario()
      assert Usuario.conectar(usuario) == %{usuario | conectado: true}
    end
  end

  describe "to_linea/1 y de_linea/1" do
    test "cabecera coincide con el formato del issue" do
      assert Usuario.cabecera() == "username;password_hash;nombre_completo;tipo;zona"
    end

    test "to_linea genera 5 campos y no guarda conectado" do
      linea = Usuario.to_linea(Fabrica.usuario(conectado: true))

      assert linea == "laura;#{@hash_1234};Laura Gómez;coordinador;centro"
      assert length(CSV.separar(linea)) == 5
    end

    test "ida y vuelta devuelve el mismo usuario" do
      usuario = Fabrica.usuario()
      assert {:ok, ^usuario} = usuario |> Usuario.to_linea() |> Usuario.de_linea()
    end

    test "ida y vuelta funciona con cada tipo" do
      for tipo <- Usuario.tipos() do
        usuario = Fabrica.usuario(tipo: tipo)
        assert {:ok, ^usuario} = usuario |> Usuario.to_linea() |> Usuario.de_linea()
      end
    end

    test "al cargar, conectado siempre es false" do
      usuario = Fabrica.usuario(conectado: true)

      assert {:ok, cargado} = usuario |> Usuario.to_linea() |> Usuario.de_linea()
      assert cargado.conectado == false
      assert cargado == %{usuario | conectado: false}
    end

    test "un usuario cargado todavía puede autenticarse" do
      {:ok, cargado} = Fabrica.usuario() |> Usuario.to_linea() |> Usuario.de_linea()
      assert {:ok, _} = Usuario.autenticar(cargado, Fabrica.contrasena())
    end

    test "de_linea rechaza una línea con menos o más de 5 campos" do
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;hash;Laura;coordinador")
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;hash;Laura;coordinador;centro;x")
    end

    test "de_linea rechaza un tipo desconocido" do
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;hash;Laura;jefe;centro")
    end

    test "de_linea rechaza campos vacíos" do
      assert {:error, :linea_invalida} = Usuario.de_linea(";hash;Laura;coordinador;centro")
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;;Laura;coordinador;centro")
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;hash;;coordinador;centro")
      assert {:error, :linea_invalida} = Usuario.de_linea("laura;hash;Laura;coordinador;")
    end

    test "de_linea rechaza una línea vacía o que no es texto" do
      assert {:error, :linea_invalida} = Usuario.de_linea("")
      assert {:error, :linea_invalida} = Usuario.de_linea(nil)
    end

    @tag :tmp_dir
    test "ida y vuelta por un archivo CSV", %{tmp_dir: dir} do
      ruta = Path.join(dir, "usuarios.csv")
      usuarios = [Fabrica.usuario(), Fabrica.usuario(username: "pedro", tipo: :voluntario)]

      assert :ok = CSV.escribir(ruta, Usuario.cabecera(), usuarios, &Usuario.to_linea/1)
      assert {:ok, ^usuarios} = CSV.leer(ruta, &Usuario.de_linea/1)
    end

    @tag :tmp_dir
    test "CSV.leer reporta la línea corrupta", %{tmp_dir: dir} do
      ruta = Path.join(dir, "usuarios.csv")

      contenido =
        Usuario.cabecera() <> "\n" <> Usuario.to_linea(Fabrica.usuario()) <> "\nbasura\n"

      assert :ok = File.write(ruta, contenido)

      assert {:error, {:linea_invalida, 3}} = CSV.leer(ruta, &Usuario.de_linea/1)
    end
  end
end
