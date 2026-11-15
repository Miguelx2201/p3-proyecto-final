defmodule EmergenciasTest do
  # Los servidores tienen nombre fijo y comparten `data_dir`: no puede ser async.
  use ExUnit.Case, async: false

  import Emergencias

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Fabrica
  alias Emergencias.Procesos.AlbergueServer
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
        "emergencias_fachada_#{System.unique_integer([:positive])}"
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

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp iniciar(especificacion) do
    assert {:ok, _pid} = start_supervised(especificacion)
    :ok
  end

  # Lo registra el mismo proceso de la prueba y `listar/1` va después en el
  # mismo buzón, así que ya está procesado.
  defp actividades(username) do
    assert {:ok, lista} = RegistroActividad.listar(username)
    lista
  end

  defp recurso(id) do
    assert {:ok, recurso} = RecursosServer.obtener(id)
    recurso
  end

  defp necesidad(id) do
    assert {:ok, necesidad} = NecesidadesServer.obtener(id)
    necesidad
  end

  defp zona_centro(coordinador) do
    assert {:ok, _zona} = register_zone(coordinador, "centro", "Zona Centro", :critico)
    :ok
  end

  defp agua_50(coordinador) do
    assert {:ok, _recurso} =
             register_resource(coordinador, "R001", :agua, 50, "litros", "centro_acopio_1")

    :ok
  end

  defp necesidad_agua(coordinador, cantidad \\ 30) do
    assert {:ok, %Necesidad{}} =
             register_need(
               coordinador,
               :agua,
               cantidad,
               :critica,
               "centro",
               "Punto de atención sector 3"
             )

    :ok
  end

  defp persona(usuario, documento \\ "1094", estado \\ :reportada) do
    assert {:ok, %Persona{}} = report_person(usuario, documento, "Andrés", 30, "centro", estado)
    :ok
  end

  defp albergue(coordinador, codigo \\ "A01", capacidad \\ 10, ocupacion \\ 0) do
    assert {:ok, %Albergue{}} =
             register_shelter(
               coordinador,
               codigo,
               "Albergue Norte",
               "centro",
               capacidad,
               ocupacion
             )

    :ok
  end

  defp mascota(usuario, tipo) do
    assert {:ok, %Mascota{}} =
             report_pet(usuario, tipo, "perro", "Luna", "negra", :mediano, "centro", "3001234567")

    :ok
  end

  # ---------------------------------------------------------------------------
  # Sesión y actividad
  # ---------------------------------------------------------------------------

  describe "connect/4 y disconnect/1" do
    test "registra un usuario nuevo y lo devuelve conectado" do
      assert {:ok, %Usuario{username: "ana", tipo: :voluntario, conectado: true} = usuario} =
               connect("ana", "1234", :voluntario, "centro")

      assert usuario.zona == "centro"

      assert [%{comando: "connect", resultado: "ok"}] = actividades("ana")
    end

    test "un usuario existente se autentica con su contraseña" do
      assert {:ok, _usuario} = connect("ana", "1234", :voluntario, "centro")
      assert {:ok, %Usuario{conectado: true}} = connect("ana", "1234", :voluntario, "centro")
    end

    test "contraseña incorrecta: credenciales inválidas y queda registrado" do
      assert {:ok, _usuario} = connect("ana", "1234", :voluntario, "centro")
      assert {:error, :credenciales_invalidas} = connect("ana", "otra", :voluntario, "centro")

      assert [%{resultado: "ok"}, %{resultado: "error:credenciales_invalidas"}] =
               actividades("ana")
    end

    test "tipo inválido" do
      assert {:error, :tipo_invalido} = connect("ana", "1234", :rey, "centro")
      assert [%{comando: "connect", resultado: "error:tipo_invalido"}] = actividades("ana")
    end

    test "disconnect desconecta y una segunda vez da :no_conectado" do
      assert {:ok, usuario} = connect("ana", "1234", :voluntario, "centro")

      assert :ok = disconnect(usuario)
      assert {:error, :no_conectado} = disconnect(usuario)

      assert [%{comando: "connect"}, %{comando: "disconnect", resultado: "ok"}, ultimo] =
               actividades("ana")

      assert ultimo.resultado == "error:no_conectado"
    end
  end

  describe "usuario inválido" do
    test "sin una struct Usuario no se hace nada" do
      assert {:error, :usuario_invalido} = pending_needs(nil)
      assert {:error, :usuario_invalido} = register_zone(%{tipo: :coordinador}, "a", "A", :alto)
      assert {:ok, []} = NecesidadesServer.listar()
    end
  end

  # ---------------------------------------------------------------------------
  # Zonas
  # ---------------------------------------------------------------------------

  describe "zonas" do
    test "register_zone, register_sector, register_point, zone_status y zone_stats", %{
      coordinador: c,
      ciudadano: ciudadano
    } do
      assert {:ok, %{codigo: "centro", nivel: :critico}} =
               register_zone(c, "centro", "Zona Centro", :critico)

      assert {:ok, _zona} = register_sector(c, "centro", "S1", "Sector 1", 200)
      assert {:ok, _zona} = register_point(c, "centro", "S1", "P1", "Punto 3", 40)

      assert {:ok, %{codigo: "centro", nombre: "Zona Centro"}} = zone_status(ciudadano, "centro")
      assert {:ok, %{}} = zone_stats(c, "centro")
      assert [%{comando: "register_zone", resultado: "ok"} | _] = actividades("laura")
    end

    test "zona duplicada y nivel inválido", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :id_duplicado} = register_zone(c, "centro", "Otra", :alto)
      assert {:error, :nivel_invalido} = register_zone(c, "norte", "Norte", :enorme)
    end

    test "zona inexistente", %{coordinador: c, ciudadano: ciudadano} do
      assert {:error, :no_encontrado} = zone_status(ciudadano, "nada")
      assert {:error, :no_encontrado} = zone_stats(c, "nada")
      assert {:error, :no_encontrado} = register_sector(c, "nada", "S1", "Sector 1", 10)
      assert {:error, :no_encontrado} = register_point(c, "nada", "S1", "P1", "Punto", 10)
    end

    test "cantidad de personas inválida", %{coordinador: c} do
      zona_centro(c)
      assert {:error, :cantidad_invalida} = register_sector(c, "centro", "S1", "Sector 1", -1)
    end

    test "permisos: solo coordinador o administrador", %{
      voluntario: voluntario,
      ciudadano: ciudadano,
      coordinador: c
    } do
      zona_centro(c)

      assert {:error, :permiso_denegado} = register_zone(voluntario, "norte", "Norte", :alto)
      assert {:error, :permiso_denegado} = register_sector(voluntario, "centro", "S1", "S", 1)
      assert {:error, :permiso_denegado} = register_point(voluntario, "centro", "S1", "P", "P", 1)
      assert {:error, :permiso_denegado} = zone_stats(ciudadano, "centro")
      assert {:ok, _zona} = zone_status(ciudadano, "centro")
    end
  end

  # ---------------------------------------------------------------------------
  # Necesidades
  # ---------------------------------------------------------------------------

  describe "register_need/6" do
    test "registra la necesidad asociada a la zona y deja la actividad", %{
      ciudadano: ciudadano,
      coordinador: c
    } do
      zona_centro(c)

      assert {:ok,
              %Necesidad{
                id: "N001",
                tipo: :agua,
                cantidad_requerida: 30,
                prioridad: :critica,
                zona: "centro",
                responsable: "carlos",
                estado: :pendiente,
                asociada_a: {:zona, "centro"}
              }} =
               register_need(ciudadano, :agua, 30, :critica, "centro", "Punto sector 3")

      assert [%{comando: "register_need", resultado: "ok"}] = actividades("carlos")
    end

    test "zona inexistente: no se crea la necesidad", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} =
               register_need(c, :agua, 30, :critica, "nada", "Punto sector 3")

      assert {:ok, []} = NecesidadesServer.listar()
      assert [%{resultado: "error:zona_no_encontrada"}] = actividades("laura")
    end

    test "validaciones de la necesidad", %{coordinador: c} do
      zona_centro(c)

      assert {:error, :cantidad_invalida} = register_need(c, :agua, 0, :critica, "centro", "x")
      assert {:error, :prioridad_invalida} = register_need(c, :agua, 5, :urgente, "centro", "x")
      assert {:error, :tipo_invalido} = register_need(c, :lava, 5, :critica, "centro", "x")
      assert {:error, :descripcion_vacia} = register_need(c, :agua, 5, :critica, "centro", "")
      assert {:error, :tipo_otro_requerido} = register_need(c, :otra, 5, :critica, "centro", "x")
    end
  end

  describe "consulta y cambio de estado de necesidades" do
    setup %{coordinador: c} do
      zona_centro(c)
      necesidad_agua(c)
      assert {:ok, _} = register_need(c, :alimentos, 10, :baja, "centro", "Comida")
      :ok
    end

    test "list_needs filtra y ordena por prioridad; pending_needs", %{ciudadano: ciudadano} do
      assert {:ok, [%{id: "N001"}, %{id: "N002"}]} = list_needs(ciudadano)
      assert {:ok, [%{id: "N002"}]} = list_needs(ciudadano, tipo: :alimentos)
      assert {:ok, [%{id: "N001"}, %{id: "N002"}]} = pending_needs(ciudadano)
    end

    test "set_need_status con transición válida e inválida", %{coordinador: c} do
      assert {:ok, %Necesidad{estado: :asignada}} = set_need_status(c, "N001", :asignada)
      assert {:error, :transicion_invalida} = set_need_status(c, "N002", :atendida)
      assert {:error, :no_encontrado} = set_need_status(c, "N999", :asignada)
    end

    test "cancel_need cancela y una segunda vez da :ya_cerrada", %{coordinador: c} do
      assert {:ok, %Necesidad{estado: :cancelada}} = cancel_need(c, "N001")
      assert {:error, :ya_cerrada} = cancel_need(c, "N001")
      assert {:error, :no_encontrado} = cancel_need(c, "N999")
    end

    test "permisos de estado y cancelación", %{voluntario: voluntario, ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = set_need_status(voluntario, "N001", :asignada)
      assert {:error, :permiso_denegado} = cancel_need(ciudadano, "N001")
      assert %Necesidad{estado: :pendiente} = necesidad("N001")
    end
  end

  # ---------------------------------------------------------------------------
  # Recursos
  # ---------------------------------------------------------------------------

  describe "register_resource/7" do
    test "el nombre es la categoría y la zona por defecto la del usuario", %{coordinador: c} do
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
              }} = register_resource(c, "R001", :agua, 50, "litros", "centro_acopio_1")
    end

    test "con zona explícita", %{coordinador: c} do
      zona_centro(c)
      assert {:ok, _} = register_zone(c, "norte", "Zona Norte", :alto)

      assert {:ok, %Recurso{zona: "norte"}} =
               register_resource(c, "R001", :agua, 50, "litros", "bodega", "norte")
    end

    test "zona inexistente (explícita o por defecto)", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} =
               register_resource(c, "R001", :agua, 50, "litros", "bodega", "nada")

      assert {:error, :zona_no_encontrada} =
               register_resource(c, "R001", :agua, 50, "litros", "bodega")

      assert {:ok, []} = RecursosServer.listar()
    end

    test "validaciones del recurso", %{coordinador: c} do
      zona_centro(c)
      agua_50(c)

      assert {:error, :id_duplicado} = register_resource(c, "R001", :agua, 5, "litros", "b")
      assert {:error, :categoria_invalida} = register_resource(c, "R002", :lava, 5, "l", "b")
      assert {:error, :cantidad_invalida} = register_resource(c, "R002", :agua, -1, "l", "b")
      assert {:error, :texto_vacio} = register_resource(c, "R002", :agua, 5, "", "b")
    end

    test "permisos: coordinador o administrador", %{voluntario: voluntario} do
      assert {:error, :permiso_denegado} =
               register_resource(voluntario, "R001", :agua, 50, "litros", "bodega")
    end
  end

  describe "list_resources/2" do
    setup %{coordinador: c} do
      zona_centro(c)
      agua_50(c)
      assert {:ok, _} = register_resource(c, "R002", :alimentos, 20, "kg", "bodega")
      :ok
    end

    test "un voluntario lista y filtra", %{voluntario: voluntario} do
      assert {:ok, [%{id: "R001"}, %{id: "R002"}]} = list_resources(voluntario)
      assert {:ok, [%{id: "R002"}]} = list_resources(voluntario, categoria: :alimentos)
    end

    test "un ciudadano no puede", %{ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = list_resources(ciudadano)
    end
  end

  describe "add_stock/3 y remove_stock/3" do
    setup %{coordinador: c} do
      zona_centro(c)
      agua_50(c)
    end

    test "entrada y salida cambian el inventario", %{coordinador: c} do
      assert {:ok, %{recurso: %{cantidad_disponible: 60}}} = add_stock(c, "R001", 10)
      assert {:ok, %{recurso: %{cantidad_disponible: 25}}} = remove_stock(c, "R001", 35)
    end

    test "validaciones", %{coordinador: c} do
      assert {:error, :sin_stock} = remove_stock(c, "R001", 51)
      assert {:error, :cantidad_invalida} = add_stock(c, "R001", 0)
      assert {:error, :recurso_no_encontrado} = add_stock(c, "R999", 1)
      assert recurso("R001").cantidad_disponible == 50
    end

    test "permisos", %{voluntario: voluntario} do
      assert {:error, :permiso_denegado} = add_stock(voluntario, "R001", 1)
      assert {:error, :permiso_denegado} = remove_stock(voluntario, "R001", 1)
    end
  end

  describe "transfer_resource/5" do
    setup %{coordinador: c} do
      zona_centro(c)
      agua_50(c)
    end

    test "mueve inventario al centro destino", %{coordinador: c} do
      assert {:ok, %{origen: origen, destino: destino}} =
               transfer_resource(c, "R001", "centro_acopio_1", "centro_acopio_2", 20)

      assert origen.cantidad_disponible == 30
      assert destino.cantidad_disponible == 20
      assert destino.ubicacion == "centro_acopio_2"
    end

    test "el centro de origen debe ser la ubicación del recurso", %{coordinador: c} do
      assert {:error, :centro_origen_invalido} =
               transfer_resource(c, "R001", "otro_centro", "centro_acopio_2", 20)

      assert recurso("R001").cantidad_disponible == 50
    end

    test "sin stock, recurso inexistente y permisos", %{coordinador: c, voluntario: voluntario} do
      assert {:error, :sin_stock} =
               transfer_resource(c, "R001", "centro_acopio_1", "centro_acopio_2", 51)

      assert {:error, :recurso_no_encontrado} =
               transfer_resource(c, "R999", "centro_acopio_1", "centro_acopio_2", 1)

      assert {:error, :permiso_denegado} =
               transfer_resource(voluntario, "R001", "centro_acopio_1", "centro_acopio_2", 1)
    end
  end

  describe "critical_resources/1" do
    setup %{coordinador: c} do
      zona_centro(c)
      agua_50(c)
    end

    test "detecta el déficit entre demanda y disponibilidad", %{coordinador: c} do
      necesidad_agua(c, 80)

      assert {:ok, [par]} = critical_resources(c)

      assert par == %{zona: "centro", categoria: :agua, disponible: 50, demanda: 80, deficit: 30}
    end

    test "sin déficit devuelve lista vacía", %{coordinador: c} do
      necesidad_agua(c, 30)
      assert {:ok, []} = critical_resources(c)
    end

    test "permisos", %{voluntario: voluntario} do
      assert {:error, :permiso_denegado} = critical_resources(voluntario)
    end
  end

  # ---------------------------------------------------------------------------
  # assign_resource/4
  # ---------------------------------------------------------------------------

  describe "assign_resource/4" do
    setup %{coordinador: c} do
      zona_centro(c)
      agua_50(c)
      necesidad_agua(c, 30)
    end

    test "flujo completo de la plantilla: agua 50 L y necesidad de 30 L", %{coordinador: c} do
      assert {:ok, %{necesidad: necesidad, movimientos: movimientos}} =
               assign_resource(c, "N001", :agua, 30)

      assert %Necesidad{id: "N001", cantidad_asignada: 30, estado: :asignada} = necesidad
      assert Enum.sum(Enum.map(movimientos, & &1.cantidad)) == 30
      assert Enum.all?(movimientos, &(&1.tipo == :asignacion and &1.recurso_id == "R001"))
      assert recurso("R001").cantidad_disponible == 20
      assert %Necesidad{cantidad_asignada: 30, estado: :asignada} = necesidad("N001")

      assert {:ok, resumen} = summary(c)
      assert resumen.recursos_por_categoria.agua == 20
      assert resumen.necesidades_pendientes.critica == 0

      assert [_zona, _recurso, _necesidad, %{comando: "assign_resource", resultado: "ok"} | _] =
               actividades("laura")
    end

    test "un ciudadano recibe :permiso_denegado", %{ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = assign_resource(ciudadano, "N001", :agua, 30)
      assert recurso("R001").cantidad_disponible == 50

      assert [%{comando: "assign_resource", resultado: "error:permiso_denegado"}] =
               actividades("carlos")
    end

    test "un voluntario tampoco puede", %{voluntario: voluntario} do
      assert {:error, :permiso_denegado} = assign_resource(voluntario, "N001", :agua, 30)
    end

    test "necesidad inexistente", %{coordinador: c} do
      assert {:error, :no_encontrado} = assign_resource(c, "N999", :agua, 30)
    end

    test "categoría incompatible: no toca el inventario", %{coordinador: c} do
      assert {:error, :categoria_incompatible} = assign_resource(c, "N001", :alimentos, 30)
      assert recurso("R001").cantidad_disponible == 50
    end

    test "necesidad cerrada", %{coordinador: c} do
      assert {:ok, _} = cancel_need(c, "N001")

      assert {:error, :ya_cerrada} = assign_resource(c, "N001", :agua, 10)
      assert recurso("R001").cantidad_disponible == 50
    end

    test "sin stock suficiente", %{coordinador: c} do
      assert {:ok, _} = remove_stock(c, "R001", 45)

      assert {:error, :sin_stock} = assign_resource(c, "N001", :agua, 30)
      assert recurso("R001").cantidad_disponible == 5
      assert necesidad("N001").cantidad_asignada == 0
    end

    test "cantidad inválida", %{coordinador: c} do
      assert {:error, :cantidad_invalida} = assign_resource(c, "N001", :agua, 0)
      assert recurso("R001").cantidad_disponible == 50
    end

    test "asignaciones parciales hasta cubrir la necesidad", %{coordinador: c} do
      assert {:ok, %{necesidad: %{cantidad_asignada: 10, estado: :pendiente}}} =
               assign_resource(c, "N001", :agua, 10)

      assert {:ok, %{necesidad: %{cantidad_asignada: 30, estado: :asignada}}} =
               assign_resource(c, "N001", :agua, 20)

      assert recurso("R001").cantidad_disponible == 20
    end

    test "si registrar la asignación falla, se devuelve la reserva", %{coordinador: c} do
      # Hay stock (50) pero la necesidad solo requiere 30: reservar funciona y
      # `registrar_asignacion` responde :excede_requerido.
      assert {:error, :excede_requerido} = assign_resource(c, "N001", :agua, 40)

      assert recurso("R001").cantidad_disponible == 50
      assert %Necesidad{cantidad_asignada: 0, estado: :pendiente} = necesidad("N001")
    end

    test "solicitudes simultáneas no superan lo requerido ni pierden inventario", %{
      coordinador: c
    } do
      resultados =
        1..5
        |> Task.async_stream(fn _ -> assign_resource(c, "N001", :agua, 10) end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 3
      assert Enum.count(resultados, &(&1 == {:error, :excede_requerido})) == 2
      assert %Necesidad{cantidad_asignada: 30, estado: :asignada} = necesidad("N001")
      assert recurso("R001").cantidad_disponible == 20
    end
  end

  # ---------------------------------------------------------------------------
  # Personas y mensajes
  # ---------------------------------------------------------------------------

  describe "report_person/6 y find_person/2" do
    setup %{coordinador: c} do
      zona_centro(c)
    end

    test "cualquier usuario reporta y se encuentra por documento o filtros", %{
      ciudadano: ciudadano
    } do
      assert {:ok, %Persona{documento: "1094", nombre: "Andrés", estado: :reportada}} =
               report_person(ciudadano, "1094", "Andrés", 30, "centro", :reportada)

      assert {:ok, [%Persona{documento: "1094"}]} = find_person(ciudadano, "1094")
      assert {:ok, [%Persona{documento: "1094"}]} = find_person(ciudadano, zona: "centro")
      assert {:ok, []} = find_person(ciudadano, "0000")
      assert {:error, :filtros_invalidos} = find_person(ciudadano, :nada)
    end

    test "zona inexistente y validaciones", %{ciudadano: ciudadano} do
      assert {:error, :zona_no_encontrada} =
               report_person(ciudadano, "1", "Ana", 30, "nada", :reportada)

      persona(ciudadano)

      assert {:error, :id_duplicado} =
               report_person(ciudadano, "1094", "Otro", 30, "centro", :reportada)

      assert {:error, :edad_invalida} =
               report_person(ciudadano, "2", "Ana", -1, "centro", :reportada)

      assert {:error, :estado_invalido} = report_person(ciudadano, "3", "Ana", 3, "centro", :raro)
    end
  end

  describe "set_person_state/3" do
    setup %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      persona(ciudadano)
    end

    test "un voluntario avanza el estado", %{voluntario: voluntario} do
      assert {:ok, %Persona{estado: :localizada}} =
               set_person_state(voluntario, "1094", :localizada)
    end

    test "transiciones inválidas y persona inexistente", %{voluntario: voluntario} do
      assert {:ok, _} = set_person_state(voluntario, "1094", :trasladada)

      assert {:error, :transicion_invalida} = set_person_state(voluntario, "1094", :reportada)
      assert {:error, :mismo_estado} = set_person_state(voluntario, "1094", :trasladada)
      assert {:error, :persona_no_encontrada} = set_person_state(voluntario, "0000", :localizada)
    end

    test "un ciudadano no puede", %{ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = set_person_state(ciudadano, "1094", :localizada)
    end
  end

  describe "mensajes familiares" do
    setup %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      persona(ciudadano)
    end

    test "enviar, listar y marcar como entregado", %{
      ciudadano: ciudadano,
      voluntario: voluntario
    } do
      assert {:ok, %Mensaje{id: "MS001", remitente: "carlos", estado: :pendiente}} =
               send_family_message(ciudadano, "1094", "Estoy bien")

      assert {:ok, [%Mensaje{id: "MS001"}]} = list_family_messages(ciudadano, "1094")

      assert {:ok, %Mensaje{estado: :entregado}} = mark_message_delivered(voluntario, "MS001")
      assert {:error, :ya_entregado} = mark_message_delivered(voluntario, "MS001")
    end

    test "persona o mensaje inexistente", %{ciudadano: ciudadano, voluntario: voluntario} do
      assert {:error, :persona_no_encontrada} = send_family_message(ciudadano, "0000", "Hola")
      assert {:error, :mensaje_no_encontrado} = mark_message_delivered(voluntario, "MS999")
      assert {:ok, []} = list_family_messages(ciudadano, "0000")
    end

    test "un ciudadano no marca entregados", %{ciudadano: ciudadano} do
      assert {:ok, _} = send_family_message(ciudadano, "1094", "Hola")
      assert {:error, :permiso_denegado} = mark_message_delivered(ciudadano, "MS001")
    end
  end

  # ---------------------------------------------------------------------------
  # Mascotas
  # ---------------------------------------------------------------------------

  describe "report_pet/9 y list_pets/2" do
    setup %{coordinador: c} do
      zona_centro(c)
    end

    test "reporta (nombre desconocido queda en nil) y lista con filtros", %{
      ciudadano: ciudadano
    } do
      assert {:ok, %Mascota{id: "M001", tipo: :perdida, nombre: nil, estado: :activa}} =
               report_pet(
                 ciudadano,
                 :perdida,
                 "perro",
                 "desconocido",
                 "negra",
                 :mediano,
                 "centro",
                 "300"
               )

      assert {:ok, %Mascota{caracteristicas: "collar rojo"}} =
               report_pet(
                 ciudadano,
                 :encontrada,
                 "gato",
                 "Misi",
                 "gris",
                 :pequeno,
                 "centro",
                 "300",
                 "collar rojo"
               )

      assert {:ok, [%{id: "M001"}, %{id: "M002"}]} = list_pets(ciudadano)
      assert {:ok, [%{id: "M002"}]} = list_pets(ciudadano, especie: "gato")
    end

    test "zona inexistente y validaciones", %{ciudadano: ciudadano} do
      assert {:error, :zona_no_encontrada} =
               report_pet(ciudadano, :perdida, "perro", "Luna", "negra", :mediano, "nada", "300")

      assert {:error, :tipo_invalido} =
               report_pet(ciudadano, :rara, "perro", "Luna", "negra", :mediano, "centro", "300")

      assert {:error, :tamano_invalido} =
               report_pet(ciudadano, :perdida, "perro", "Luna", "negra", :enorme, "centro", "300")

      assert {:error, :contacto_vacio} =
               report_pet(ciudadano, :perdida, "perro", "Luna", "negra", :mediano, "centro", "")

      assert {:ok, []} = list_pets(ciudadano)
    end
  end

  describe "match_pets/1 y confirm_pet_match/3" do
    setup %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      mascota(ciudadano, :perdida)
      mascota(ciudadano, :encontrada)
    end

    test "registra la pareja como posible coincidencia", %{voluntario: voluntario} do
      assert {:ok, [%{perdida_id: "M001", encontrada_id: "M002", puntaje: puntaje}]} =
               match_pets(voluntario)

      assert is_number(puntaje)

      assert {:ok, [%{id: "M001"}, %{id: "M002"}]} =
               list_pets(voluntario, estado: :posible_coincidencia)
    end

    test "no repite mascotas: dos perdidas iguales y una encontrada dan un solo par", %{
      voluntario: voluntario,
      ciudadano: ciudadano
    } do
      mascota(ciudadano, :perdida)

      assert {:ok, [%{perdida_id: "M001", encontrada_id: "M002"}]} = match_pets(voluntario)
      assert {:ok, [%{id: "M003", estado: :activa}]} = list_pets(voluntario, estado: :activa)
    end

    test "sin coincidencias devuelve lista vacía", %{voluntario: voluntario} do
      assert {:ok, [_par]} = match_pets(voluntario)
      assert {:ok, []} = match_pets(voluntario)
    end

    test "confirm_pet_match cierra ambos reportes", %{voluntario: voluntario} do
      assert {:ok, [_par]} = match_pets(voluntario)

      assert {:ok, {%Mascota{estado: :resuelta}, %Mascota{estado: :resuelta}}} =
               confirm_pet_match(voluntario, "M001", "M002")

      assert {:error, :ya_resuelta} = confirm_pet_match(voluntario, "M001", "M002")
      assert {:error, :no_encontrada} = confirm_pet_match(voluntario, "M001", "M999")
    end

    test "un ciudadano no puede", %{ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = match_pets(ciudadano)
      assert {:error, :permiso_denegado} = confirm_pet_match(ciudadano, "M001", "M002")
    end
  end

  # ---------------------------------------------------------------------------
  # Albergues
  # ---------------------------------------------------------------------------

  describe "register_shelter/6 y check_shelter/2" do
    setup %{coordinador: c} do
      zona_centro(c)
    end

    test "registra el albergue y se consulta", %{coordinador: c, ciudadano: ciudadano} do
      assert {:ok, %Albergue{id: "A01", capacidad_maxima: 10, ocupacion_actual: 0}} =
               register_shelter(c, "A01", "Albergue Norte", "centro", 10)

      assert {:ok, %Albergue{id: "A01", zona: "centro"} = albergue} =
               check_shelter(ciudadano, "A01")

      assert Albergue.cupos_disponibles(albergue) == 10
    end

    test "con ocupación inicial", %{coordinador: c} do
      assert {:ok, %Albergue{ocupacion_actual: 4}} =
               register_shelter(c, "A01", "Albergue Norte", "centro", 10, 4)
    end

    test "zona inexistente, id duplicado y datos inválidos", %{coordinador: c} do
      assert {:error, :zona_no_encontrada} = register_shelter(c, "A01", "Norte", "nada", 10)

      albergue(c)

      assert {:error, :id_duplicado} = register_shelter(c, "A01", "Otro", "centro", 10)
      assert {:error, :capacidad_invalida} = register_shelter(c, "A02", "Otro", "centro", -1)

      assert {:error, :ocupacion_supera_capacidad} =
               register_shelter(c, "A02", "Otro", "centro", 5, 6)
    end

    test "albergue inexistente y permisos", %{
      coordinador: c,
      voluntario: voluntario,
      ciudadano: ciudadano
    } do
      assert {:error, :no_encontrado} = check_shelter(ciudadano, "A99")
      assert {:error, :permiso_denegado} = register_shelter(voluntario, "A01", "N", "centro", 10)
      assert {:ok, _} = register_shelter(c, "A01", "N", "centro", 10)
    end
  end

  describe "register_entry/3 y register_exit/3" do
    setup %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      albergue(c)
      persona(ciudadano)
    end

    test "el ingreso ocupa un cupo y pasa la persona a :en_albergue", %{voluntario: voluntario} do
      assert {:ok, %Albergue{ocupacion_actual: 1}} = register_entry(voluntario, "A01", "1094")

      assert {:ok, %Persona{estado: :en_albergue}} = PersonasServer.obtener("1094")
    end

    test "persona o albergue inexistente", %{voluntario: voluntario} do
      assert {:error, :persona_no_encontrada} = register_entry(voluntario, "A01", "0000")
      assert {:error, :no_encontrado} = register_entry(voluntario, "A99", "1094")

      assert {:ok, %Albergue{ocupacion_actual: 0}} = AlbergueServer.consultar("A01")
      assert {:ok, %Persona{estado: :reportada}} = PersonasServer.obtener("1094")
    end

    test "sin cupo y documento ya registrado", %{coordinador: c, voluntario: voluntario} do
      assert {:ok, _} = register_shelter(c, "A02", "Sin cupo", "centro", 0)
      assert {:error, :sin_cupo} = register_entry(voluntario, "A02", "1094")

      assert {:ok, _} = register_entry(voluntario, "A01", "1094")
      assert {:error, :ya_registrado} = register_entry(voluntario, "A01", "1094")
    end

    test "si el cambio de estado falla se revierte el ingreso", %{
      coordinador: c,
      voluntario: voluntario
    } do
      persona(c, "2000", :reunificada)

      assert {:error, :transicion_invalida} = register_entry(voluntario, "A01", "2000")

      assert {:ok, %Albergue{ocupacion_actual: 0, personas: personas}} =
               AlbergueServer.consultar("A01")

      assert MapSet.size(personas) == 0
      assert {:ok, %Persona{estado: :reunificada}} = PersonasServer.obtener("2000")
    end

    test "una persona que ya estaba :en_albergue puede ingresar", %{
      coordinador: c,
      voluntario: voluntario
    } do
      persona(c, "3000", :en_albergue)

      assert {:ok, %Albergue{ocupacion_actual: 1}} = register_entry(voluntario, "A01", "3000")
    end

    test "la salida libera el cupo", %{voluntario: voluntario} do
      assert {:ok, _} = register_entry(voluntario, "A01", "1094")

      assert {:ok, %Albergue{ocupacion_actual: 0}} = register_exit(voluntario, "A01", "1094")
      assert {:error, :persona_no_esta} = register_exit(voluntario, "A01", "1094")
      assert {:error, :no_encontrado} = register_exit(voluntario, "A99", "1094")
    end

    test "un ciudadano no puede", %{ciudadano: ciudadano} do
      assert {:error, :permiso_denegado} = register_entry(ciudadano, "A01", "1094")
      assert {:error, :permiso_denegado} = register_exit(ciudadano, "A01", "1094")
    end
  end

  describe "shelter_report/2" do
    setup %{coordinador: c} do
      zona_centro(c)
      albergue(c, "A01", 10, 5)
      albergue(c, "A02", 10, 9)
    end

    test "devuelve los más ocupados", %{coordinador: c} do
      assert {:ok, [%Albergue{id: "A02"}]} = shelter_report(c, 1)
      assert {:ok, [%Albergue{id: "A02"}, %Albergue{id: "A01"}]} = shelter_report(c)
    end

    test "n inválido y permisos", %{coordinador: c, voluntario: voluntario} do
      assert {:error, :cantidad_invalida} = shelter_report(c, -1)
      assert {:error, :cantidad_invalida} = shelter_report(c, "dos")
      assert {:error, :permiso_denegado} = shelter_report(voluntario)
    end
  end

  # ---------------------------------------------------------------------------
  # Resumen
  # ---------------------------------------------------------------------------

  describe "summary/1" do
    test "con el sistema vacío", %{coordinador: c} do
      assert {:ok, resumen} = summary(c)

      assert resumen == %{
               recursos_por_categoria: Map.new(Recurso.categorias(), &{&1, 0}),
               necesidades_pendientes: %{critica: 0, alta: 0, media: 0, baja: 0},
               personas_localizadas: 0,
               mensajes: %{total: 0, pendientes: 0},
               mascotas: %{activas: 0, posibles: 0, resueltas: 0},
               albergues: %{capacidad_total: 0, ocupacion_total: 0},
               zonas: []
             }
    end

    test "reúne los datos de todos los servidores", %{coordinador: c, ciudadano: ciudadano} do
      zona_centro(c)
      agua_50(c)
      necesidad_agua(c)
      persona(ciudadano, "1094", :localizada)
      assert {:ok, _} = send_family_message(ciudadano, "1094", "Estoy bien")
      mascota(ciudadano, :perdida)
      albergue(c, "A01", 10, 4)

      assert {:ok, resumen} = summary(c)

      assert resumen.recursos_por_categoria.agua == 50
      assert resumen.necesidades_pendientes.critica == 1
      assert resumen.personas_localizadas == 1
      assert resumen.mensajes == %{total: 1, pendientes: 1}
      assert resumen.mascotas == %{activas: 1, posibles: 0, resueltas: 0}
      assert resumen.albergues == %{capacidad_total: 10, ocupacion_total: 4}
      assert [%{codigo: "centro", nombre: "Zona Centro", nivel: :critico}] = resumen.zonas
    end

    test "permisos: solo coordinador o administrador", %{
      voluntario: voluntario,
      ciudadano: ciudadano
    } do
      assert {:error, :permiso_denegado} = summary(voluntario)
      assert {:error, :permiso_denegado} = summary(ciudadano)
    end
  end
end
