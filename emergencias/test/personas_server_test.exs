defmodule Emergencias.Procesos.PersonasServerTest do
  # No es async: el servidor tiene nombre fijo y la carpeta de datos es una
  # variable global de la aplicación.
  use ExUnit.Case, async: false

  alias Emergencias.Fabrica
  alias Emergencias.Persistencia
  alias Emergencias.Procesos.PersonasServer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    anterior = Application.get_env(:emergencias, :data_dir)
    Application.put_env(:emergencias, :data_dir, tmp_dir)
    on_exit(fn -> restaurar_data_dir(anterior) end)
    :ok
  end

  defp restaurar_data_dir(nil), do: Application.delete_env(:emergencias, :data_dir)
  defp restaurar_data_dir(valor), do: Application.put_env(:emergencias, :data_dir, valor)

  defp iniciar, do: start_supervised!(PersonasServer)

  defp reportar_persona(documento \\ "1094", estado \\ :localizada),
    do: PersonasServer.reportar(documento, "Andrés", 30, "centro", estado, "laura")

  # ---------------------------------------------------------------------------
  # reportar/6
  # ---------------------------------------------------------------------------

  describe "reportar/6" do
    test "registra una persona válida y la guarda en disco" do
      iniciar()

      assert {:ok, persona} = reportar_persona()
      assert persona.documento == "1094"
      assert persona.estado == :localizada
      assert [%{de: nil, a: :localizada, usuario: "laura"}] = persona.historial
      assert {:ok, ^persona} = PersonasServer.obtener("1094")

      assert {:ok, [guardada]} = Persistencia.cargar_personas()
      assert guardada.documento == "1094"
      assert [%{de: nil, a: :localizada}] = guardada.historial
    end

    test "rechaza un documento ya registrado con :id_duplicado" do
      iniciar()
      assert {:ok, _persona} = reportar_persona()

      assert {:error, :id_duplicado} =
               PersonasServer.reportar("1094", "Otro", 20, "norte", :reportada, "laura")

      assert {:ok, [_sola]} = Persistencia.cargar_personas()
    end

    test "el documento duplicado se detecta aunque traiga espacios" do
      iniciar()
      assert {:ok, _persona} = reportar_persona()

      assert {:error, :id_duplicado} =
               PersonasServer.reportar(" 1094 ", "Otro", 20, "norte", :reportada, "laura")
    end

    test "rechaza documento vacío" do
      iniciar()

      assert {:error, :documento_vacio} =
               PersonasServer.reportar("  ", "Andrés", 30, "centro", :localizada, "laura")
    end

    test "rechaza nombre vacío" do
      iniciar()

      assert {:error, :nombre_vacio} =
               PersonasServer.reportar("1094", "", 30, "centro", :localizada, "laura")
    end

    test "rechaza edad inválida" do
      iniciar()

      assert {:error, :edad_invalida} =
               PersonasServer.reportar("1094", "Andrés", 121, "centro", :localizada, "laura")

      assert {:error, :edad_invalida} =
               PersonasServer.reportar("1094", "Andrés", "30", "centro", :localizada, "laura")
    end

    test "rechaza zona vacía" do
      iniciar()

      assert {:error, :zona_vacia} =
               PersonasServer.reportar("1094", "Andrés", 30, " ", :localizada, "laura")
    end

    test "rechaza estado inválido" do
      iniciar()

      assert {:error, :estado_invalido} =
               PersonasServer.reportar("1094", "Andrés", 30, "centro", :perdida, "laura")
    end

    test "rechaza usuario vacío" do
      iniciar()

      assert {:error, :usuario_vacio} =
               PersonasServer.reportar("1094", "Andrés", 30, "centro", :localizada, "")
    end

    test "una persona inválida no queda registrada" do
      iniciar()

      assert {:error, :nombre_vacio} =
               PersonasServer.reportar("1094", "", 30, "centro", :reportada, "laura")

      assert {:error, :persona_no_encontrada} = PersonasServer.obtener("1094")
      assert {:ok, []} = Persistencia.cargar_personas()
    end

    test "si no se puede guardar, devuelve el error y no cambia el estado" do
      iniciar()
      data_dir = Application.get_env(:emergencias, :data_dir)

      # Una carpeta de datos que cuelga de un archivo no se puede crear.
      archivo = Path.join(data_dir, "bloqueado")
      assert :ok = File.write(archivo, "x")
      Application.put_env(:emergencias, :data_dir, Path.join(archivo, "datos"))

      assert {:error, _razon} = reportar_persona()

      Application.put_env(:emergencias, :data_dir, data_dir)
      assert {:error, :persona_no_encontrada} = PersonasServer.obtener("1094")
    end
  end

  # ---------------------------------------------------------------------------
  # obtener/1
  # ---------------------------------------------------------------------------

  describe "obtener/1" do
    test "devuelve la persona registrada" do
      iniciar()
      {:ok, persona} = reportar_persona()

      assert {:ok, ^persona} = PersonasServer.obtener("1094")
    end

    test "devuelve :persona_no_encontrada si el documento no existe" do
      iniciar()

      assert {:error, :persona_no_encontrada} = PersonasServer.obtener("999")
      assert {:error, :persona_no_encontrada} = PersonasServer.obtener(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # buscar/1
  # ---------------------------------------------------------------------------

  describe "buscar/1" do
    setup do
      iniciar()
      {:ok, _} = PersonasServer.reportar("2", "Beatriz Ruiz", 40, "norte", :reportada, "laura")
      {:ok, _} = PersonasServer.reportar("1", "Andrés Gil", 30, "centro", :localizada, "laura")
      {:ok, _} = PersonasServer.reportar("3", "Carlos Gil", 50, "centro", :reportada, "laura")
      :ok
    end

    test "sin filtros devuelve todas, ordenadas por documento" do
      assert {:ok, personas} = PersonasServer.buscar([])
      assert Enum.map(personas, & &1.documento) == ["1", "2", "3"]
    end

    test "filtra por zona" do
      assert {:ok, personas} = PersonasServer.buscar(zona: "centro")
      assert Enum.map(personas, & &1.documento) == ["1", "3"]
    end

    test "filtra por estado" do
      assert {:ok, personas} = PersonasServer.buscar(estado: :reportada)
      assert Enum.map(personas, & &1.documento) == ["2", "3"]
    end

    test "filtra por nombre sin distinguir mayúsculas y combina filtros" do
      assert {:ok, personas} = PersonasServer.buscar(nombre: "GIL", estado: :reportada)
      assert Enum.map(personas, & &1.documento) == ["3"]
    end

    test "filtra por documento" do
      assert {:ok, [persona]} = PersonasServer.buscar(documento: "2")
      assert persona.nombre == "Beatriz Ruiz"
    end

    test "sin coincidencias devuelve lista vacía" do
      assert {:ok, []} = PersonasServer.buscar(zona: "sur")
    end

    test "rechaza filtros que no son una lista" do
      assert {:error, :filtros_invalidos} = PersonasServer.buscar(:zona)
    end
  end

  # ---------------------------------------------------------------------------
  # cambiar_estado/3
  # ---------------------------------------------------------------------------

  describe "cambiar_estado/3" do
    test "avanza el estado, agrega al historial y guarda en disco" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:ok, persona} = PersonasServer.cambiar_estado("1094", :trasladada, "pedro")
      assert persona.estado == :trasladada
      assert [ultimo, %{de: nil}] = persona.historial
      assert %{de: :localizada, a: :trasladada, usuario: "pedro"} = ultimo

      assert {:ok, [guardada]} = Persistencia.cargar_personas()
      assert guardada.estado == :trasladada
      assert length(guardada.historial) == 2
    end

    test "permite saltos hacia adelante" do
      iniciar()
      {:ok, _persona} = reportar_persona("1094", :reportada)

      assert {:ok, %{estado: :reunificada}} =
               PersonasServer.cambiar_estado("1094", :reunificada, "pedro")
    end

    test "rechaza retroceder con :transicion_invalida" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:error, :transicion_invalida} =
               PersonasServer.cambiar_estado("1094", :reportada, "pedro")

      assert {:ok, %{estado: :localizada}} = PersonasServer.obtener("1094")
    end

    test "rechaza el mismo estado con :mismo_estado" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:error, :mismo_estado} =
               PersonasServer.cambiar_estado("1094", :localizada, "pedro")
    end

    test "rechaza un estado que no existe" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:error, :estado_invalido} =
               PersonasServer.cambiar_estado("1094", :volando, "pedro")
    end

    test "rechaza usuario vacío" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:error, :usuario_vacio} =
               PersonasServer.cambiar_estado("1094", :trasladada, " ")
    end

    test "rechaza un documento que no existe" do
      iniciar()

      assert {:error, :persona_no_encontrada} =
               PersonasServer.cambiar_estado("999", :trasladada, "pedro")
    end
  end

  # ---------------------------------------------------------------------------
  # historial/1
  # ---------------------------------------------------------------------------

  describe "historial/1" do
    test "devuelve los cambios con el más reciente primero" do
      iniciar()
      {:ok, _persona} = reportar_persona("1094", :reportada)
      {:ok, _persona} = PersonasServer.cambiar_estado("1094", :localizada, "pedro")
      {:ok, _persona} = PersonasServer.cambiar_estado("1094", :en_albergue, "ana")

      assert {:ok, historial} = PersonasServer.historial("1094")
      assert Enum.map(historial, & &1.a) == [:en_albergue, :localizada, :reportada]
      assert Enum.map(historial, & &1.de) == [:localizada, :reportada, nil]
    end

    test "devuelve :persona_no_encontrada si el documento no existe" do
      iniciar()

      assert {:error, :persona_no_encontrada} = PersonasServer.historial("999")
    end
  end

  # ---------------------------------------------------------------------------
  # enviar_mensaje/3
  # ---------------------------------------------------------------------------

  describe "enviar_mensaje/3" do
    setup do
      iniciar()
      {:ok, _persona} = reportar_persona()
      :ok
    end

    test "crea un mensaje pendiente con id MS001 y lo guarda en disco" do
      assert {:ok, mensaje} = PersonasServer.enviar_mensaje("laura", "1094", "Estamos bien")
      assert mensaje.id == "MS001"
      assert mensaje.estado == :pendiente
      assert mensaje.remitente == "laura"
      assert mensaje.documento_destinatario == "1094"

      assert {:ok, [guardado]} = Persistencia.cargar_mensajes()
      assert guardado.id == "MS001"
    end

    test "los ids siguen la secuencia MS001, MS002..." do
      {:ok, primero} = PersonasServer.enviar_mensaje("laura", "1094", "Uno")
      {:ok, segundo} = PersonasServer.enviar_mensaje("laura", "1094", "Dos")

      assert {primero.id, segundo.id} == {"MS001", "MS002"}
    end

    test "rechaza un documento no registrado con :persona_no_encontrada" do
      assert {:error, :persona_no_encontrada} =
               PersonasServer.enviar_mensaje("laura", "999", "Hola")

      assert {:ok, []} = Persistencia.cargar_mensajes()
    end

    test "un envío fallido no consume el número de id" do
      assert {:error, :persona_no_encontrada} =
               PersonasServer.enviar_mensaje("laura", "999", "Hola")

      assert {:error, :contenido_vacio} = PersonasServer.enviar_mensaje("laura", "1094", " ; ")

      assert {:ok, %{id: "MS001"}} = PersonasServer.enviar_mensaje("laura", "1094", "Hola")
    end

    test "rechaza remitente vacío" do
      assert {:error, :remitente_vacio} = PersonasServer.enviar_mensaje("", "1094", "Hola")
    end

    test "rechaza documento vacío" do
      assert {:error, :documento_vacio} = PersonasServer.enviar_mensaje("laura", "  ", "Hola")
    end

    test "rechaza contenido vacío" do
      assert {:error, :contenido_vacio} = PersonasServer.enviar_mensaje("laura", "1094", "   ")
    end
  end

  # ---------------------------------------------------------------------------
  # listar_mensajes/1
  # ---------------------------------------------------------------------------

  describe "listar_mensajes/1" do
    test "devuelve solo los mensajes del documento, en orden de id" do
      iniciar()
      {:ok, _persona} = reportar_persona("1")
      {:ok, _persona} = reportar_persona("2")
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("laura", "1", "Uno")
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("laura", "2", "Para otro")
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("pedro", "1", "Dos")

      assert {:ok, mensajes} = PersonasServer.listar_mensajes("1")
      assert Enum.map(mensajes, & &1.id) == ["MS001", "MS003"]
      assert Enum.map(mensajes, & &1.contenido) == ["Uno", "Dos"]
    end

    test "devuelve lista vacía si no hay mensajes" do
      iniciar()
      {:ok, _persona} = reportar_persona()

      assert {:ok, []} = PersonasServer.listar_mensajes("1094")
      assert {:ok, []} = PersonasServer.listar_mensajes("999")
    end
  end

  # ---------------------------------------------------------------------------
  # marcar_entregado/1
  # ---------------------------------------------------------------------------

  describe "marcar_entregado/1" do
    setup do
      iniciar()
      {:ok, _persona} = reportar_persona()
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("laura", "1094", "Estamos bien")
      :ok
    end

    test "marca el mensaje como entregado y lo guarda en disco" do
      assert {:ok, %{id: "MS001", estado: :entregado}} = PersonasServer.marcar_entregado("MS001")
      assert {:ok, [%{estado: :entregado}]} = PersonasServer.listar_mensajes("1094")
      assert {:ok, [%{estado: :entregado}]} = Persistencia.cargar_mensajes()
    end

    test "rechaza un mensaje ya entregado con :ya_entregado" do
      assert {:ok, _mensaje} = PersonasServer.marcar_entregado("MS001")
      assert {:error, :ya_entregado} = PersonasServer.marcar_entregado("MS001")
    end

    test "rechaza un id que no existe con :mensaje_no_encontrado" do
      assert {:error, :mensaje_no_encontrado} = PersonasServer.marcar_entregado("MS999")
      assert {:error, :mensaje_no_encontrado} = PersonasServer.marcar_entregado(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Arranque desde disco
  # ---------------------------------------------------------------------------

  describe "arranque" do
    test "recupera personas, historial y mensajes guardados y sigue la numeración" do
      iniciar()
      {:ok, _persona} = reportar_persona()
      {:ok, _persona} = PersonasServer.cambiar_estado("1094", :trasladada, "pedro")
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("laura", "1094", "Uno")
      {:ok, _mensaje} = PersonasServer.enviar_mensaje("laura", "1094", "Dos")
      assert :ok = stop_supervised(PersonasServer)

      iniciar()

      assert {:ok, persona} = PersonasServer.obtener("1094")
      assert persona.estado == :trasladada
      assert length(persona.historial) == 2
      assert {:ok, [_uno, _dos]} = PersonasServer.listar_mensajes("1094")
      assert {:ok, %{id: "MS003"}} = PersonasServer.enviar_mensaje("laura", "1094", "Tres")
    end

    test "carga las entidades de la fábrica guardadas por Persistencia" do
      persona = Fabrica.persona(documento: "55", nombre: "Marta")
      mensaje = Fabrica.mensaje(id: "MS007", documento_destinatario: "55")
      assert :ok = Persistencia.guardar_personas([persona])
      assert :ok = Persistencia.guardar_mensajes([mensaje])

      iniciar()

      assert {:ok, %{nombre: "Marta"}} = PersonasServer.obtener("55")
      assert {:ok, [%{id: "MS007"}]} = PersonasServer.listar_mensajes("55")
      assert {:ok, %{id: "MS008"}} = PersonasServer.enviar_mensaje("laura", "55", "Hola")
    end

    test "no arranca si un archivo está corrupto" do
      Process.flag(:trap_exit, true)
      ruta = Emergencias.CSV.ruta(Emergencias.Dominio.Persona.archivo_csv())
      assert :ok = File.mkdir_p(Path.dirname(ruta))
      assert :ok = File.write(ruta, "documento;nombre;edad;zona;estado\nbasura\n")

      assert {:error, {:linea_invalida, 2}} = PersonasServer.start_link()
    end
  end
end
