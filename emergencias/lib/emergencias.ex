defmodule Emergencias do
  @moduledoc """
  Fachada del sistema: la única API que usan la consola y las pruebas.

  Cada función recibe al usuario (`Emergencias.Dominio.Usuario`) como primer
  argumento y siempre hace lo mismo:

    1. verifica el permiso con `Permisos.verificar/2`;
    2. valida las referencias (por ejemplo, que la zona exista);
    3. llama a los servidores;
    4. registra la actividad en `RegistroActividad`.

  Resultados: `{:ok, valor}` o `{:error, razon}` con `razon` átomo. Las únicas
  excepciones son `disconnect/1`, que devuelve `:ok` como `UsuariosServer`, y
  los errores de usuario inválido (`{:error, :usuario_invalido}`, que no se
  registran porque no hay a quién atribuirlos).

  Esta fachada no cambia nada de los módulos de dominio, servicios ni
  servidores: solo los combina.
  """

  require Logger

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Procesos.AlbergueServer
  alias Emergencias.Procesos.AlberguesSupervisor
  alias Emergencias.Procesos.MascotasServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.Procesos.RegistroActividad
  alias Emergencias.Procesos.UsuariosServer
  alias Emergencias.Procesos.ZonasServer
  alias Emergencias.Servicios.Permisos
  alias Emergencias.Servicios.ReportesServicio

  # Estados cerrados de `Necesidad` (el dominio no los expone con una función
  # pública; `ReportesServicio` los repite por la misma razón).
  @necesidad_cerrada [:atendida, :cancelada]

  # ---------------------------------------------------------------------------
  # Sesión
  # ---------------------------------------------------------------------------

  @doc """
  Conecta (o registra y conecta) a un usuario. Devuelve `{:ok, usuario}` con el
  usuario ya conectado y registra la actividad con el `username` recibido.

  No verifica permiso: todavía no hay un usuario autenticado y `connect` está
  permitido para todos los tipos. Un `tipo` inválido da `:tipo_invalido`.
  """
  def connect(username, password, tipo, zona) do
    resultado =
      with {:ok, usuario, _modo} <- UsuariosServer.conectar(username, password, tipo, zona) do
        {:ok, usuario}
      end

    registrar_actividad(username, :connect, resultado)
    resultado
  end

  @doc "Desconecta al usuario. Devuelve `:ok` o `{:error, razon}`."
  def disconnect(usuario) do
    ejecutar(usuario, :disconnect, fn -> UsuariosServer.desconectar(usuario.username) end)
  end

  # ---------------------------------------------------------------------------
  # Zonas
  # ---------------------------------------------------------------------------

  @doc "Registra una zona. Ver `ZonasServer.registrar_zona/3`."
  def register_zone(usuario, codigo, nombre, nivel) do
    ejecutar(usuario, :register_zone, fn ->
      ZonasServer.registrar_zona(codigo, nombre, nivel)
    end)
  end

  @doc "Registra un sector en una zona. Devuelve la zona actualizada."
  def register_sector(usuario, zona, codigo, nombre, personas) do
    ejecutar(usuario, :register_sector, fn ->
      ZonasServer.registrar_sector(zona, codigo, nombre, personas)
    end)
  end

  @doc "Registra un punto de atención en un sector. Devuelve la zona actualizada."
  def register_point(usuario, zona, sector, codigo, nombre, personas) do
    ejecutar(usuario, :register_point, fn ->
      ZonasServer.registrar_punto(zona, sector, codigo, nombre, personas)
    end)
  end

  @doc "Consulta una zona. Devuelve `{:ok, zona}` o `{:error, :no_encontrado}`."
  def zone_status(usuario, zona) do
    ejecutar(usuario, :zone_status, fn -> ZonasServer.consultar(zona) end)
  end

  @doc "Estadísticas de una zona. Devuelve `{:ok, mapa}` o `{:error, :no_encontrado}`."
  def zone_stats(usuario, zona) do
    ejecutar(usuario, :zone_stats, fn -> ZonasServer.estadisticas(zona) end)
  end

  # ---------------------------------------------------------------------------
  # Necesidades
  # ---------------------------------------------------------------------------

  @doc """
  Registra una necesidad asociada a su zona.

  Error extra: `:zona_no_encontrada`. Como el comando no recibe `tipo_otro`, una
  necesidad de tipo `:otra` falla con `:tipo_otro_requerido`.
  """
  def register_need(usuario, tipo, cantidad, prioridad, zona, descripcion) do
    ejecutar(usuario, :register_need, fn ->
      with :ok <- verificar_zona(zona) do
        NecesidadesServer.registrar(
          tipo,
          nil,
          cantidad,
          prioridad,
          zona,
          descripcion,
          usuario.username,
          {:zona, zona}
        )
      end
    end)
  end

  @doc "Lista necesidades; `filtros` admite `zona:`, `tipo:`, `prioridad:` y `estado:`."
  def list_needs(usuario, filtros \\ []) do
    ejecutar(usuario, :list_needs, fn -> NecesidadesServer.listar(filtros) end)
  end

  @doc "Necesidades pendientes, ordenadas por prioridad."
  def pending_needs(usuario) do
    ejecutar(usuario, :pending_needs, fn -> NecesidadesServer.pendientes() end)
  end

  @doc "Cambia el estado de una necesidad según las transiciones de `Necesidad`."
  def set_need_status(usuario, id, estado) do
    ejecutar(usuario, :set_need_status, fn -> NecesidadesServer.cambiar_estado(id, estado) end)
  end

  @doc "Cancela una necesidad."
  def cancel_need(usuario, id) do
    ejecutar(usuario, :cancel_need, fn -> NecesidadesServer.cancelar(id) end)
  end

  @doc """
  Asigna `cantidad` de la `categoria` a la necesidad `necesidad_id`.

  1. Verifica el permiso `:assign_resource`.
  2. Busca la necesidad; si su tipo no es la categoría, `:categoria_incompatible`;
     si está cerrada, `:ya_cerrada`.
  3. Reserva el inventario (`RecursosServer.reservar/5`, atómico).
  4. Registra la asignación en la necesidad.
  5. Si el paso 4 falla, devuelve la reserva con `RecursosServer.devolver/1` y
     entrega el error del paso 4.

  Devuelve `{:ok, %{necesidad: necesidad, movimientos: movimientos}}`.
  """
  def assign_resource(usuario, necesidad_id, categoria, cantidad) do
    ejecutar(usuario, :assign_resource, fn ->
      asignar(usuario.username, necesidad_id, categoria, cantidad)
    end)
  end

  defp asignar(username, id, categoria, cantidad) do
    with {:ok, necesidad} <- NecesidadesServer.obtener(id),
         :ok <- verificar_categoria(necesidad, categoria),
         :ok <- verificar_abierta(necesidad),
         {:ok, %{movimientos: movimientos}} <-
           RecursosServer.reservar(necesidad.tipo, necesidad.zona, cantidad, id, username) do
      confirmar_asignacion(id, cantidad, movimientos)
    end
  end

  defp verificar_categoria(%{tipo: categoria}, categoria), do: :ok
  defp verificar_categoria(_necesidad, _categoria), do: {:error, :categoria_incompatible}

  defp verificar_abierta(%{estado: estado}) when estado in @necesidad_cerrada,
    do: {:error, :ya_cerrada}

  defp verificar_abierta(_necesidad), do: :ok

  # Los pasos 3 y 4 ocurren en procesos distintos, sin transacción: si el 4 falla
  # hay que deshacer la reserva a mano.
  defp confirmar_asignacion(id, cantidad, movimientos) do
    case NecesidadesServer.registrar_asignacion(id, cantidad) do
      {:ok, necesidad} ->
        {:ok, %{necesidad: necesidad, movimientos: movimientos}}

      {:error, _razon} = error ->
        devolver_reserva(movimientos)
        error
    end
  end

  defp devolver_reserva(movimientos) do
    case RecursosServer.devolver(movimientos) do
      {:ok, _respuesta} ->
        :ok

      {:error, razon} ->
        Logger.error("No se pudo devolver la reserva #{inspect(movimientos)}: #{inspect(razon)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Recursos
  # ---------------------------------------------------------------------------

  @doc """
  Registra un recurso. El nombre es el texto de la categoría; si no se da `zona`
  se usa la zona principal del usuario. La zona debe existir.
  """
  def register_resource(usuario, id, categoria, cantidad, unidad, ubicacion, zona \\ nil) do
    ejecutar(usuario, :register_resource, fn ->
      zona = zona || usuario.zona

      with :ok <- verificar_zona(zona) do
        RecursosServer.registrar(
          id,
          nombre_de_categoria(categoria),
          categoria,
          cantidad,
          unidad,
          ubicacion,
          zona
        )
      end
    end)
  end

  defp nombre_de_categoria(categoria) when is_atom(categoria), do: Atom.to_string(categoria)
  defp nombre_de_categoria(_otro), do: ""

  @doc "Lista recursos; `filtros` admite `categoria:`, `zona:` y `ubicacion:`."
  def list_resources(usuario, filtros \\ []) do
    ejecutar(usuario, :list_resources, fn -> RecursosServer.listar(filtros) end)
  end

  @doc "Suma `cantidad` al inventario del recurso `id`."
  def add_stock(usuario, id, cantidad) do
    ejecutar(usuario, :add_stock, fn ->
      RecursosServer.entrada(id, cantidad, usuario.username)
    end)
  end

  @doc "Resta `cantidad` al inventario del recurso `id`."
  def remove_stock(usuario, id, cantidad) do
    ejecutar(usuario, :remove_stock, fn ->
      RecursosServer.salida(id, cantidad, usuario.username)
    end)
  end

  @doc """
  Transfiere `cantidad` del recurso `id` al centro `centro_destino`.

  Error extra: `:centro_origen_invalido` si `centro_origen` no es la ubicación
  del recurso.
  """
  def transfer_resource(usuario, id, centro_origen, centro_destino, cantidad) do
    ejecutar(usuario, :transfer_resource, fn ->
      with {:ok, recurso} <- RecursosServer.obtener(id),
           :ok <- verificar_origen(recurso, centro_origen) do
        RecursosServer.transferir(id, centro_destino, cantidad, usuario.username)
      end
    end)
  end

  defp verificar_origen(%{ubicacion: ubicacion}, ubicacion), do: :ok
  defp verificar_origen(_recurso, _centro), do: {:error, :centro_origen_invalido}

  @doc "Pares zona/categoría cuya disponibilidad no cubre la demanda."
  def critical_resources(usuario) do
    ejecutar(usuario, :critical_resources, fn ->
      with {:ok, recursos} <- RecursosServer.listar(),
           {:ok, necesidades} <- NecesidadesServer.listar() do
        {:ok, ReportesServicio.recursos_criticos(recursos, necesidades)}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Personas y mensajes
  # ---------------------------------------------------------------------------

  @doc "Reporta una persona. La zona debe existir."
  def report_person(usuario, documento, nombre, edad, zona, estado) do
    ejecutar(usuario, :report_person, fn ->
      with :ok <- verificar_zona(zona) do
        PersonasServer.reportar(documento, nombre, edad, zona, estado, usuario.username)
      end
    end)
  end

  @doc """
  Busca personas. Con un texto busca por documento; con una lista usa los
  filtros `nombre:`, `zona:` y `estado:` (y `documento:`).
  """
  def find_person(usuario, documento) when is_binary(documento),
    do: find_person(usuario, documento: documento)

  def find_person(usuario, filtros) do
    ejecutar(usuario, :find_person, fn -> PersonasServer.buscar(filtros) end)
  end

  @doc "Cambia el estado de una persona."
  def set_person_state(usuario, documento, estado) do
    ejecutar(usuario, :set_person_state, fn ->
      PersonasServer.cambiar_estado(documento, estado, usuario.username)
    end)
  end

  @doc "Deja un mensaje familiar para la persona con ese documento."
  def send_family_message(usuario, documento, contenido) do
    ejecutar(usuario, :send_family_message, fn ->
      PersonasServer.enviar_mensaje(usuario.username, documento, contenido)
    end)
  end

  @doc "Mensajes dirigidos a la persona con ese documento."
  def list_family_messages(usuario, documento) do
    ejecutar(usuario, :list_family_messages, fn -> PersonasServer.listar_mensajes(documento) end)
  end

  @doc "Marca un mensaje como entregado."
  def mark_message_delivered(usuario, id) do
    ejecutar(usuario, :mark_message_delivered, fn -> PersonasServer.marcar_entregado(id) end)
  end

  # ---------------------------------------------------------------------------
  # Mascotas
  # ---------------------------------------------------------------------------

  @doc """
  Reporta una mascota. `tipo` es `:perdida` o `:encontrada` (convertir
  `lost`/`found` es trabajo de la consola). La zona debe existir.
  """
  def report_pet(
        usuario,
        tipo,
        especie,
        nombre,
        color,
        tamano,
        zona,
        contacto,
        caracteristicas \\ ""
      ) do
    ejecutar(usuario, :report_pet, fn ->
      with :ok <- verificar_zona(zona) do
        MascotasServer.reportar(
          tipo,
          especie,
          nombre,
          caracteristicas,
          color,
          tamano,
          zona,
          contacto
        )
      end
    end)
  end

  @doc "Lista reportes de mascotas; `filtros` admite `especie:`, `zona:` y `estado:`."
  def list_pets(usuario, filtros \\ []) do
    ejecutar(usuario, :list_pets, fn -> MascotasServer.consultar(filtros) end)
  end

  @doc """
  Calcula las coincidencias entre mascotas perdidas y encontradas y registra
  como posible coincidencia el mejor par de cada mascota, sin repetir ninguna.

  Se eligen por puntaje descendente (empates por id); los pares que el servidor
  rechace se omiten. Devuelve `{:ok, [%{perdida_id, encontrada_id, puntaje}]}`
  con los pares registrados.
  """
  def match_pets(usuario) do
    ejecutar(usuario, :match_pets, fn ->
      with {:ok, coincidencias} <- MascotasServer.buscar_coincidencias() do
        registrados =
          coincidencias
          |> mejores_parejas()
          |> Enum.filter(&registrar_pareja/1)

        {:ok, registrados}
      end
    end)
  end

  defp mejores_parejas(coincidencias) do
    coincidencias
    |> Enum.sort_by(fn par -> {-par.puntaje, par.perdida_id, par.encontrada_id} end)
    |> Enum.reduce({[], MapSet.new()}, fn par, {elegidos, usados} ->
      if MapSet.member?(usados, par.perdida_id) or MapSet.member?(usados, par.encontrada_id) do
        {elegidos, usados}
      else
        usados = usados |> MapSet.put(par.perdida_id) |> MapSet.put(par.encontrada_id)
        {[par | elegidos], usados}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp registrar_pareja(par) do
    match?(
      {:ok, _pareja},
      MascotasServer.registrar_posible_coincidencia(par.perdida_id, par.encontrada_id)
    )
  end

  @doc "Cierra ambos reportes (`:resuelta`). Devuelve `{:ok, {perdida, encontrada}}`."
  def confirm_pet_match(usuario, id_perdida, id_encontrada) do
    ejecutar(usuario, :confirm_pet_match, fn ->
      MascotasServer.confirmar_coincidencia(id_perdida, id_encontrada)
    end)
  end

  # ---------------------------------------------------------------------------
  # Albergues
  # ---------------------------------------------------------------------------

  @doc """
  Registra un albergue y arranca su proceso. La zona debe existir.
  Devuelve `{:ok, albergue}`.
  """
  def register_shelter(usuario, codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    ejecutar(usuario, :register_shelter, fn ->
      with :ok <- verificar_zona(zona),
           {:ok, albergue} <- Albergue.crear(codigo, nombre, zona, capacidad, ocupacion),
           {:ok, _pid} <- AlberguesSupervisor.registrar(albergue) do
        {:ok, albergue}
      end
    end)
  end

  @doc "Estado del albergue (usar `Albergue.cupos_disponibles/1` para los cupos)."
  def check_shelter(usuario, codigo) do
    ejecutar(usuario, :check_shelter, fn -> AlbergueServer.consultar(codigo) end)
  end

  @doc """
  Registra el ingreso de una persona a un albergue y la pasa a `:en_albergue`.

  Verifica que la persona exista, llama a `AlbergueServer.ingreso/2` y cambia el
  estado de la persona. Si ese cambio falla, revierte con
  `AlbergueServer.salida/2` y devuelve el error. Si la persona ya estaba
  `:en_albergue` el ingreso se considera correcto.
  """
  def register_entry(usuario, albergue_id, documento) do
    ejecutar(usuario, :register_entry, fn ->
      with {:ok, _persona} <- PersonasServer.obtener(documento),
           {:ok, albergue} <- AlbergueServer.ingreso(albergue_id, documento) do
        pasar_a_albergue(albergue, albergue_id, documento, usuario.username)
      end
    end)
  end

  defp pasar_a_albergue(albergue, albergue_id, documento, username) do
    case PersonasServer.cambiar_estado(documento, :en_albergue, username) do
      {:ok, _persona} ->
        {:ok, albergue}

      {:error, :mismo_estado} ->
        {:ok, albergue}

      {:error, _razon} = error ->
        revertir_ingreso(albergue_id, documento)
        error
    end
  end

  defp revertir_ingreso(albergue_id, documento) do
    case AlbergueServer.salida(albergue_id, documento) do
      {:ok, _albergue} ->
        :ok

      {:error, razon} ->
        Logger.error(
          "No se pudo revertir el ingreso de #{documento} a #{albergue_id}: #{inspect(razon)}"
        )
    end
  end

  @doc "Registra la salida de una persona del albergue."
  def register_exit(usuario, albergue_id, documento) do
    ejecutar(usuario, :register_exit, fn -> AlbergueServer.salida(albergue_id, documento) end)
  end

  @doc "Los `n` albergues con mayor ocupación (por defecto 5). `n` debe ser entero >= 0."
  def shelter_report(usuario, n \\ 5) do
    ejecutar(usuario, :shelter_report, fn ->
      if is_integer(n) and n >= 0 do
        with {:ok, albergues} <- AlberguesSupervisor.listar() do
          {:ok, ReportesServicio.albergues_mas_ocupados(albergues, n)}
        end
      else
        {:error, :cantidad_invalida}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Resumen
  # ---------------------------------------------------------------------------

  @doc """
  Reúne los datos de todos los servidores y devuelve
  `{:ok, ReportesServicio.resumen_global(datos)}`.

  Los datos se leen servidor por servidor, no en una instantánea atómica.
  """
  def summary(usuario) do
    ejecutar(usuario, :summary, fn ->
      with {:ok, necesidades} <- NecesidadesServer.listar(),
           {:ok, recursos} <- RecursosServer.listar(),
           {:ok, personas} <- PersonasServer.buscar([]),
           {:ok, mensajes} <- mensajes_de(personas),
           {:ok, mascotas} <- MascotasServer.consultar([]),
           {:ok, albergues} <- AlberguesSupervisor.listar() do
        {:ok,
         ReportesServicio.resumen_global(%{
           zonas: ZonasServer.listar(),
           necesidades: necesidades,
           recursos: recursos,
           personas: personas,
           mensajes: mensajes,
           mascotas: mascotas,
           albergues: albergues
         })}
      end
    end)
  end

  # Todo mensaje es para una persona registrada, así que se recorren las personas.
  defp mensajes_de(personas) do
    personas
    |> Enum.reduce_while({:ok, []}, fn persona, {:ok, acumulado} ->
      case PersonasServer.listar_mensajes(persona.documento) do
        {:ok, lista} -> {:cont, {:ok, [lista | acumulado]}}
        {:error, _razon} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, listas} -> {:ok, listas |> Enum.reverse() |> Enum.concat()}
      {:error, _razon} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Comunes
  # ---------------------------------------------------------------------------

  # Verifica el permiso, ejecuta la acción y registra la actividad.
  defp ejecutar(%Usuario{} = usuario, comando, accion) do
    resultado =
      case Permisos.verificar(usuario.tipo, comando) do
        :ok -> accion.()
        {:error, _razon} = error -> error
      end

    registrar_actividad(usuario.username, comando, resultado)
    resultado
  end

  defp ejecutar(_otro, _comando, _accion), do: {:error, :usuario_invalido}

  defp verificar_zona(zona) do
    if ZonasServer.existe?(zona), do: :ok, else: {:error, :zona_no_encontrada}
  end

  # `Actividad.nuevo/3` solo acepta comandos de texto (un átomo queda vacío y no
  # se registraría), por eso se convierte. Un error con razón que no es átomo
  # tampoco se podría registrar: se guarda como `:error_interno`.
  defp registrar_actividad(username, comando, resultado) do
    RegistroActividad.registrar(username, Atom.to_string(comando), para_registro(resultado))
  end

  defp para_registro({:error, razon}) when not is_atom(razon), do: {:error, :error_interno}
  defp para_registro(resultado), do: resultado
end
