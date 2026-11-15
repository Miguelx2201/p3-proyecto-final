defmodule Emergencias.CLI.ComandosTest do
  # Los servidores tienen nombre fijo y comparten `data_dir`: no puede ser async.
  use ExUnit.Case, async: false

  alias Emergencias.CLI.Comandos
  alias Emergencias.CLI.Formato
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Recurso
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

  # Registra la zona "centro" y el recurso R001 (50 litros de agua).
  defp recurso_r001(coordinador) do
    zona_centro(coordinador)

    assert {:ok, %Recurso{id: "R001"}} =
             Comandos.ejecutar(coordinador, :register_resource, [
               "R001",
               :agua,
               50,
               "litros",
               "centro_acopio_1"
             ])

    :ok
  end

  # Registra una necesidad y devuelve su id (la zona "centro" ya debe existir).
  defp necesidad(coordinador, tipo \\ :agua, cantidad \\ 30, prioridad \\ :critica) do
    assert {:ok, %Necesidad{id: id}} =
             Comandos.ejecutar(coordinador, :register_need, [
               tipo,
               cantidad,
               prioridad,
               "centro",
               "Punto de atención sector 3"
             ])

    id
  end

  defp disponible(coordinador, id) do
    assert {:ok, recursos} = Comandos.ejecutar(coordinador, :list_resources, [])
    assert %Recurso{cantidad_disponible: cantidad} = Enum.find(recursos, &(&1.id == id))
    cantidad
  end

  # Una categoría válida distinta de :agua (se toma del dominio, no se asume cuál).
  defp otra_categoria, do: Enum.find(Recurso.categorias(), &(&1 != :agua))

  # Lleva la necesidad por la secuencia de estados indicada (todos deben ser válidos).
  defp avanzar(coordinador, id, estados) do
    Enum.each(estados, fn estado ->
      assert {:ok, %Necesidad{estado: ^estado}} =
               Comandos.ejecutar(coordinador, :set_need_status, [id, estado])
    end)
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
  # Necesidades
  # ---------------------------------------------------------------------------

  describe "register_need" do
    test "válido", %{coordinador: c} do
      zona_centro(c)

      assert {:ok,
              %Necesidad{
                tipo: :agua,
                cantidad_requerida: 30,
                prioridad: :critica,
                zona: "centro",
                estado: :pendiente
              }} =
               Comandos.ejecutar(c, :register_need, [
                 :agua,
                 30,
                 :critica,
                 "centro",
                 "Punto de atención sector 3"
               ])
    end

    test "inválido: zona inexistente", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} =
               Comandos.ejecutar(c, :register_need, [:agua, 30, :critica, "nada", "desc"])
    end

    test "inválido: cantidad", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :cantidad_invalida} =
               Comandos.ejecutar(c, :register_need, [:agua, 0, :critica, "centro", "desc"])
    end

    test "inválido: tipo `otra` sin detalle", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :tipo_otro_requerido} =
               Comandos.ejecutar(c, :register_need, [:otra, 10, :alta, "centro", "desc"])
    end

    test "inválido: tipo", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :tipo_invalido} =
               Comandos.ejecutar(c, :register_need, [:hack, 10, :alta, "centro", "desc"])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 5}} =
               Comandos.ejecutar(c, :register_need, [:agua, 30])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :register_need, [:agua, 30, :alta, "centro", "d"])
    end
  end

  describe "list_needs" do
    test "válido: ordena de mayor a menor prioridad", %{coordinador: c} do
      zona_centro(c)
      baja = necesidad(c, :agua, 5, :baja)
      critica = necesidad(c, otra_categoria(), 5, :critica)

      assert {:ok, [primera, segunda]} = Comandos.ejecutar(c, :list_needs, [])
      assert primera.id == critica
      assert segunda.id == baja
    end

    test "válido: sin necesidades devuelve una lista vacía", %{coordinador: c} do
      assert {:ok, []} = Comandos.ejecutar(c, :list_needs, [])
    end

    test "válido: con filtros", %{coordinador: c} do
      zona_centro(c)
      _baja = necesidad(c, :agua, 5, :baja)
      critica = necesidad(c, otra_categoria(), 5, :critica)

      assert {:ok, [%Necesidad{id: ^critica}]} =
               Comandos.ejecutar(c, :list_needs, zona: "centro", prioridad: :critica)

      assert {:ok, []} = Comandos.ejecutar(c, :list_needs, zona: "otra")
    end

    test "inválido: los filtros no son una keyword list", %{coordinador: c} do
      assert {:error, :valor_invalido} = Comandos.ejecutar(c, :list_needs, ["zona=centro"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :list_needs, [])
    end
  end

  describe "pending_needs" do
    test "válido: solo pendientes, ordenadas por prioridad", %{coordinador: c} do
      zona_centro(c)
      baja = necesidad(c, :agua, 5, :baja)
      critica = necesidad(c, otra_categoria(), 5, :critica)
      cancelada = necesidad(c, otra_categoria(), 5, :alta)
      assert {:ok, %Necesidad{estado: :cancelada}} = Comandos.ejecutar(c, :cancel_need, [cancelada])

      assert {:ok, [primera, segunda]} = Comandos.ejecutar(c, :pending_needs, [])
      assert primera.id == critica
      assert segunda.id == baja
    end

    test "inválido: no recibe argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 0}} = Comandos.ejecutar(c, :pending_needs, ["x"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :pending_needs, [])
    end
  end

  describe "set_need_status" do
    test "válido: pendiente a asignada", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)

      assert {:ok, %Necesidad{id: ^id, estado: :asignada}} =
               Comandos.ejecutar(c, :set_need_status, [id, :asignada])
    end

    test "válido: asignada a en_atencion", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      avanzar(c, id, [:asignada])

      assert {:ok, %Necesidad{estado: :en_atencion}} =
               Comandos.ejecutar(c, :set_need_status, [id, :en_atencion])
    end

    test "válido: en_atencion a atendida", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      avanzar(c, id, [:asignada, :en_atencion])

      assert {:ok, %Necesidad{estado: :atendida}} =
               Comandos.ejecutar(c, :set_need_status, [id, :atendida])
    end

    test "válido: cualquier estado abierto a cancelada", %{coordinador: c} do
      zona_centro(c)
      pendiente = necesidad(c)
      asignada = necesidad(c)
      en_atencion = necesidad(c)
      avanzar(c, asignada, [:asignada])
      avanzar(c, en_atencion, [:asignada, :en_atencion])

      for id <- [pendiente, asignada, en_atencion] do
        assert {:ok, %Necesidad{estado: :cancelada}} =
                 Comandos.ejecutar(c, :set_need_status, [id, :cancelada])
      end
    end

    test "inválido: saltarse un estado (pendiente a atendida o en_atencion)", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)

      assert {:error, :transicion_invalida} =
               Comandos.ejecutar(c, :set_need_status, [id, :atendida])

      assert {:error, :transicion_invalida} =
               Comandos.ejecutar(c, :set_need_status, [id, :en_atencion])
    end

    test "inválido: retroceder (asignada a pendiente)", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      avanzar(c, id, [:asignada])

      assert {:error, :transicion_invalida} =
               Comandos.ejecutar(c, :set_need_status, [id, :pendiente])
    end

    test "inválido: la necesidad ya está cancelada", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      assert {:ok, _necesidad} = Comandos.ejecutar(c, :cancel_need, [id])

      assert {:error, :ya_cerrada} = Comandos.ejecutar(c, :set_need_status, [id, :pendiente])
    end

    test "inválido: la necesidad ya está atendida", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      avanzar(c, id, [:asignada, :en_atencion, :atendida])

      assert {:error, :ya_cerrada} = Comandos.ejecutar(c, :set_need_status, [id, :cancelada])
    end

    test "inválido: necesidad inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} =
               Comandos.ejecutar(c, :set_need_status, ["N999", :en_proceso])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 2}} =
               Comandos.ejecutar(c, :set_need_status, ["N001"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :set_need_status, ["N001", :en_proceso])
    end
  end

  describe "cancel_need" do
    test "válido", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)

      assert {:ok, %Necesidad{id: ^id, estado: :cancelada}} =
               Comandos.ejecutar(c, :cancel_need, [id])
    end

    test "inválido: ya estaba cancelada", %{coordinador: c} do
      zona_centro(c)
      id = necesidad(c)
      assert {:ok, _necesidad} = Comandos.ejecutar(c, :cancel_need, [id])

      assert {:error, :ya_cerrada} = Comandos.ejecutar(c, :cancel_need, [id])
    end

    test "inválido: necesidad inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} = Comandos.ejecutar(c, :cancel_need, ["N999"])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 1}} = Comandos.ejecutar(c, :cancel_need, [])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :cancel_need, ["N001"])
    end
  end

  # ---------------------------------------------------------------------------
  # Recursos
  # ---------------------------------------------------------------------------

  describe "register_resource" do
    test "válido: sin zona usa la zona principal del usuario", %{coordinador: c} do
      zona_centro(c)

      assert {:ok,
              %Recurso{
                id: "R001",
                nombre: "agua",
                categoria: :agua,
                cantidad_disponible: 50,
                unidad: "litros",
                ubicacion: "centro_acopio_1",
                zona: "centro"
              }} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 50,
                 "litros",
                 "centro_acopio_1"
               ])
    end

    test "válido: con zona explícita", %{coordinador: c} do
      zona_centro(c)

      assert {:ok, _zona} =
               Comandos.ejecutar(c, :register_zone, ["norte", "Zona Norte", :alto])

      assert {:ok, %Recurso{zona: "norte"}} =
               Comandos.ejecutar(c, :register_resource, [
                 "R002",
                 otra_categoria(),
                 10,
                 "cajas",
                 "bodega",
                 "norte"
               ])
    end

    test "inválido: zona inexistente", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 50,
                 "litros",
                 "centro_acopio_1",
                 "nada"
               ])
    end

    test "inválido: sin zona y la zona del usuario no existe", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 50,
                 "litros",
                 "centro_acopio_1"
               ])
    end

    test "inválido: id repetido", %{coordinador: c} do
      recurso_r001(c)

      assert {:error, :id_duplicado} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 5,
                 "litros",
                 "otro_centro"
               ])
    end

    test "inválido: cantidad", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :cantidad_invalida} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 -1,
                 "litros",
                 "centro_acopio_1"
               ])
    end

    test "inválido: permiso", %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(ciudadano, :register_resource, [
                 "R001",
                 :agua,
                 50,
                 "litros",
                 "centro_acopio_1"
               ])
    end

    test "inválido: cantidad de argumentos (menos de 5 o más de 6)", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 5}} =
               Comandos.ejecutar(c, :register_resource, ["R001", :agua])

      assert {:error, {:argumentos, esperados: 5}} =
               Comandos.ejecutar(c, :register_resource, ["R001", :agua, 1, "l", "u", "z", "extra"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :register_resource, ["R001", :agua, 50, "litros", "u"])
    end
  end

  describe "list_resources" do
    test "válido: muestra todos los recursos", %{coordinador: c} do
      recurso_r001(c)

      assert {:ok, [%Recurso{id: "R001", cantidad_disponible: 50}]} =
               Comandos.ejecutar(c, :list_resources, [])
    end

    test "válido: con filtros", %{coordinador: c} do
      recurso_r001(c)

      assert {:ok, [%Recurso{id: "R001"}]} =
               Comandos.ejecutar(c, :list_resources, categoria: :agua, zona: "centro")

      assert {:ok, []} = Comandos.ejecutar(c, :list_resources, categoria: :ropa)
    end

    test "inválido: los filtros no son una keyword list", %{coordinador: c} do
      assert {:error, :valor_invalido} = Comandos.ejecutar(c, :list_resources, ["agua"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :list_resources, [])
    end
  end

  describe "add_stock y remove_stock" do
    test "add_stock válido", %{coordinador: c} do
      recurso_r001(c)

      assert {:ok, _resultado} = Comandos.ejecutar(c, :add_stock, ["R001", 10])
      assert disponible(c, "R001") == 60
    end

    test "add_stock inválido: recurso inexistente", %{coordinador: c} do
      assert {:error, :recurso_no_encontrado} = Comandos.ejecutar(c, :add_stock, ["R999", 10])
    end

    test "add_stock inválido: cantidad", %{coordinador: c} do
      recurso_r001(c)
      assert {:error, :cantidad_invalida} = Comandos.ejecutar(c, :add_stock, ["R001", 0])
    end

    test "add_stock inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 2}} = Comandos.ejecutar(c, :add_stock, ["R001"])
    end

    test "remove_stock válido", %{coordinador: c} do
      recurso_r001(c)

      assert {:ok, _resultado} = Comandos.ejecutar(c, :remove_stock, ["R001", 20])
      assert disponible(c, "R001") == 30
    end

    test "remove_stock inválido: sin inventario suficiente", %{coordinador: c} do
      recurso_r001(c)

      assert {:error, :sin_stock} = Comandos.ejecutar(c, :remove_stock, ["R001", 51])
      assert disponible(c, "R001") == 50
    end

    test "remove_stock inválido: recurso inexistente", %{coordinador: c} do
      assert {:error, :recurso_no_encontrado} = Comandos.ejecutar(c, :remove_stock, ["R999", 1])
    end

    test "remove_stock inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 2}} =
               Comandos.ejecutar(c, :remove_stock, ["R001", 1, 2])
    end

    test "inválido: permiso", %{coordinador: c, ciudadano: ciudadano} do
      recurso_r001(c)

      assert {:error, :permiso_denegado} = Comandos.ejecutar(ciudadano, :add_stock, ["R001", 1])

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(ciudadano, :remove_stock, ["R001", 1])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :add_stock, ["R001", 1])
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :remove_stock, ["R001", 1])
    end
  end

  describe "transfer_resource" do
    test "válido", %{coordinador: c} do
      recurso_r001(c)

      assert {:ok, _resultado} =
               Comandos.ejecutar(c, :transfer_resource, [
                 "R001",
                 "centro_acopio_1",
                 "centro_acopio_2",
                 20
               ])

      assert {:ok, recursos} = Comandos.ejecutar(c, :list_resources, [])
      assert Enum.any?(recursos, &(&1.ubicacion == "centro_acopio_2"))
    end

    test "inválido: el centro de origen no es la ubicación del recurso", %{coordinador: c} do
      recurso_r001(c)

      assert {:error, :centro_origen_invalido} =
               Comandos.ejecutar(c, :transfer_resource, ["R001", "otro", "centro_acopio_2", 20])

      assert disponible(c, "R001") == 50
    end

    test "inválido: recurso inexistente", %{coordinador: c} do
      assert {:error, :recurso_no_encontrado} =
               Comandos.ejecutar(c, :transfer_resource, ["R999", "a", "b", 1])
    end

    test "inválido: sin inventario suficiente", %{coordinador: c} do
      recurso_r001(c)

      assert {:error, :sin_stock} =
               Comandos.ejecutar(c, :transfer_resource, [
                 "R001",
                 "centro_acopio_1",
                 "centro_acopio_2",
                 51
               ])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 4}} =
               Comandos.ejecutar(c, :transfer_resource, ["R001", "a"])
    end

    test "inválido: permiso", %{coordinador: c, ciudadano: ciudadano} do
      recurso_r001(c)

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(ciudadano, :transfer_resource, [
                 "R001",
                 "centro_acopio_1",
                 "centro_acopio_2",
                 1
               ])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :transfer_resource, ["R001", "a", "b", 1])
    end
  end

  describe "assign_resource" do
    test "válido: descuenta el inventario y registra la asignación", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c)

      assert {:ok,
              %{
                necesidad: %Necesidad{id: ^id, cantidad_asignada: 30, estado: :asignada},
                movimientos: movs
              }} = Comandos.ejecutar(c, :assign_resource, [id, :agua, 30])

      assert is_list(movs)
      assert disponible(c, "R001") == 20
    end

    test "inválido: la categoría no coincide con el tipo de la necesidad", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c)

      assert {:error, :categoria_incompatible} =
               Comandos.ejecutar(c, :assign_resource, [id, :ropa, 10])

      assert disponible(c, "R001") == 50
    end

    test "inválido: no hay inventario suficiente", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c, :agua, 100)

      assert {:error, :sin_stock} = Comandos.ejecutar(c, :assign_resource, [id, :agua, 60])
      assert disponible(c, "R001") == 50
    end

    test "inválido: asignar más de lo requerido devuelve la reserva", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c, :agua, 30)

      assert {:error, :excede_requerido} =
               Comandos.ejecutar(c, :assign_resource, [id, :agua, 40])

      assert disponible(c, "R001") == 50
    end

    test "inválido: necesidad inexistente", %{coordinador: c} do
      recurso_r001(c)

      assert {:error, :no_encontrado} =
               Comandos.ejecutar(c, :assign_resource, ["N999", :agua, 10])
    end

    test "inválido: una necesidad cancelada no vuelve a consumir recursos", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c)
      assert {:ok, %Necesidad{estado: :cancelada}} = Comandos.ejecutar(c, :cancel_need, [id])

      assert {:error, :ya_cerrada} = Comandos.ejecutar(c, :assign_resource, [id, :agua, 10])
      assert disponible(c, "R001") == 50
    end

    test "inválido: una necesidad atendida no vuelve a consumir recursos", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c)
      avanzar(c, id, [:asignada, :en_atencion, :atendida])

      assert {:error, :ya_cerrada} = Comandos.ejecutar(c, :assign_resource, [id, :agua, 10])
      assert disponible(c, "R001") == 50
    end

    test "inválido: permiso", %{coordinador: c, ciudadano: ciudadano} do
      recurso_r001(c)
      id = necesidad(c)

      assert {:error, :permiso_denegado} =
               Comandos.ejecutar(ciudadano, :assign_resource, [id, :agua, 10])
    end

    test "inválido: cantidad de argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 3}} =
               Comandos.ejecutar(c, :assign_resource, ["N001", :agua])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} =
               Comandos.ejecutar(nil, :assign_resource, ["N001", :agua, 30])
    end
  end

  describe "critical_resources" do
    test "válido: la demanda supera la disponibilidad", %{coordinador: c} do
      recurso_r001(c)
      _id = necesidad(c, :agua, 80)

      assert {:ok, [%{zona: "centro", categoria: :agua, deficit: 30}]} =
               Comandos.ejecutar(c, :critical_resources, [])
    end

    test "válido: sin déficit devuelve una lista vacía", %{coordinador: c} do
      recurso_r001(c)
      _id = necesidad(c, :agua, 10)

      assert {:ok, []} = Comandos.ejecutar(c, :critical_resources, [])
    end

    test "inválido: no recibe argumentos", %{coordinador: c} do
      assert {:error, {:argumentos, esperados: 0}} =
               Comandos.ejecutar(c, :critical_resources, ["x"])
    end

    test "inválido: sin sesión" do
      assert {:error, :no_conectado} = Comandos.ejecutar(nil, :critical_resources, [])
    end
  end

  describe "flujo de punta a punta (criterio de aceptación)" do
    test "register_resource, register_need, assign_resource y list_resources dejan 20", %{
      coordinador: c
    } do
      zona_centro(c)

      assert {:ok, %Recurso{id: "R001"}} =
               Comandos.ejecutar(c, :register_resource, [
                 "R001",
                 :agua,
                 50,
                 "litros",
                 "centro_acopio_1"
               ])

      assert {:ok, %Necesidad{id: "N001"}} =
               Comandos.ejecutar(c, :register_need, [
                 :agua,
                 30,
                 :critica,
                 "centro",
                 "Punto de atención sector 3"
               ])

      assert {:ok, %{necesidad: %Necesidad{id: "N001"}}} =
               Comandos.ejecutar(c, :assign_resource, ["N001", :agua, 30])

      assert {:ok, [%Recurso{id: "R001", cantidad_disponible: 20}]} =
               Comandos.ejecutar(c, :list_resources, [])
    end
  end

  # ---------------------------------------------------------------------------
  # Otros
  # ---------------------------------------------------------------------------

  describe "otros casos" do
    test "comando que aún no tiene cláusula", %{coordinador: c} do
      assert {:error, :no_implementado} = Comandos.ejecutar(c, :summary, [])
    end

    test "argumentos que no son una lista", %{coordinador: c} do
      assert {:error, :valor_invalido} = Comandos.ejecutar(c, :zone_status, "centro")
    end

    test "sesión que no es un Usuario", %{coordinador: _c} do
      assert {:error, :usuario_invalido} =
               Comandos.ejecutar(%{tipo: :coordinador}, :zone_status, ["a"])
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

    test "errores de necesidades y recursos se muestran en español", %{coordinador: c} do
      recurso_r001(c)
      id = necesidad(c)

      incompatible = Comandos.ejecutar(c, :assign_resource, [id, :ropa, 1])
      origen = Comandos.ejecutar(c, :transfer_resource, ["R001", "otro", "destino", 1])

      assert Formato.a_texto(incompatible) ==
               "La categoría no coincide con el tipo de la necesidad."

      assert Formato.a_texto(origen) ==
               "El centro de origen no es la ubicación actual del recurso."
    end
  end
end
