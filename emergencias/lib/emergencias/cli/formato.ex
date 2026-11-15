defmodule Emergencias.CLI.Formato do
  @moduledoc """
  Convierte resultados en texto para la consola.

  Es puro: solo devuelve texto, nunca imprime (eso lo hace
  `Emergencias.CLI`). Ninguna función lanza excepciones, ni siquiera con
  valores inesperados: lo que no reconoce lo muestra con `inspect/1`.

  Las entidades se muestran con `to_string/1` (ver
  `lib/emergencias/dominio/string_chars.ex`).
  """

  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Dominio.Zona
  alias Emergencias.Servicios.Permisos

  @prioridades [:critica, :alta, :media, :baja]

  # Comandos que se pueden usar sin sesión.
  @sin_sesion [:connect, :help, :exit]

  @errores %{
    # Sesión, permisos y consola
    no_conectado: "Debe conectarse primero con: connect usuario contrasena tipo zona.",
    ya_conectado: "Ya hay una sesión iniciada. Use disconnect antes de conectarse de nuevo.",
    credenciales_invalidas: "Usuario o contraseña incorrectos.",
    permiso_denegado: "Su tipo de usuario no tiene permiso para ejecutar ese comando.",
    usuario_invalido: "La sesión no es válida.",
    comando_desconocido: "Comando desconocido. Escriba help para ver los comandos disponibles.",
    linea_vacia: "Escriba un comando. Use help para ver los comandos disponibles.",
    no_implementado: "Ese comando todavía no está disponible.",
    error_interno: "Ocurrió un error inesperado. La consola sigue activa.",
    # Búsquedas y duplicados
    no_encontrado: "No se encontró el registro solicitado.",
    zona_no_encontrada: "La zona indicada no existe.",
    id_duplicado: "Ya existe un registro con ese identificador.",
    # Cantidades e inventario
    cantidad_invalida: "La cantidad no es válida.",
    sin_stock: "No hay suficiente inventario.",
    sin_cupo: "El albergue no tiene cupo disponible.",
    capacidad_invalida: "La capacidad no es válida.",
    ocupacion_invalida: "La ocupación no es válida.",
    ocupacion_supera_capacidad: "La ocupación no puede superar la capacidad.",
    # Estados y transiciones
    transicion_invalida: "Ese cambio de estado no está permitido.",
    mismo_estado: "El registro ya tiene ese estado.",
    ya_cerrada: "La necesidad ya está cerrada (atendida o cancelada).",
    ya_resuelta: "El reporte de la mascota ya está resuelto.",
    ya_entregado: "El mensaje ya fue entregado.",
    # Valores inválidos
    categoria_incompatible: "La categoría no coincide con el tipo de la necesidad.",
    categoria_invalida: "La categoría no es válida.",
    centro_origen_invalido: "El centro de origen no es la ubicación actual del recurso.",
    tipo_otro_requerido: "Para el tipo «otra» hace falta indicar el detalle.",
    tipo_invalido: "El tipo no es válido.",
    nivel_invalido: "El nivel no es válido (critico, alto, medio o bajo).",
    estado_invalido: "El estado no es válido.",
    prioridad_invalida: "La prioridad no es válida.",
    edad_invalida: "La edad debe ser un número entre 0 y 120.",
    campo_vacio: "Hay un campo de texto vacío.",
    texto_vacio: "Hay un campo de texto vacío.",
    entero_invalido: "Debe escribir un número entero.",
    valor_invalido: "Hay un valor que no es válido."
  }

  # {comando, sintaxis, descripción}. El orden es el de `help`.
  @comandos [
    {:connect, "connect usuario contrasena tipo zona", "Inicia sesión (registra al usuario)."},
    {:disconnect, "disconnect", "Cierra la sesión."},
    {:help, "help", "Muestra esta ayuda."},
    {:exit, "exit", "Sale de la consola."},
    {:register_zone, "register_zone codigo nombre nivel", "Registra una zona."},
    {:register_sector, "register_sector zona codigo nombre personas",
     "Agrega un sector a una zona."},
    {:register_point, "register_point zona sector codigo nombre personas",
     "Agrega un punto de atención a un sector."},
    {:zone_status, "zone_status zona", "Muestra una zona con sus sectores y puntos."},
    {:zone_stats, "zone_stats zona", "Estadísticas de una zona."},
    {:register_need, "register_need tipo cantidad prioridad zona descripcion",
     "Registra una necesidad."},
    {:list_needs, "list_needs [zona=..] [tipo=..] [prioridad=..] [estado=..]",
     "Lista necesidades, de mayor a menor prioridad."},
    {:pending_needs, "pending_needs", "Lista las necesidades pendientes."},
    {:set_need_status, "set_need_status id estado", "Cambia el estado de una necesidad."},
    {:cancel_need, "cancel_need id", "Cancela una necesidad."},
    {:assign_resource, "assign_resource id categoria cantidad",
     "Asigna inventario a una necesidad."},
    {:register_resource, "register_resource id categoria cantidad unidad ubicacion [zona]",
     "Registra un recurso."},
    {:list_resources, "list_resources [categoria=..] [zona=..]", "Lista recursos."},
    {:add_stock, "add_stock id cantidad", "Suma inventario a un recurso."},
    {:remove_stock, "remove_stock id cantidad", "Resta inventario a un recurso."},
    {:transfer_resource, "transfer_resource id centro_origen centro_destino cantidad",
     "Transfiere un recurso a otro centro."},
    {:critical_resources, "critical_resources", "Recursos que no cubren la demanda."},
    {:report_person, "report_person documento nombre edad zona estado",
     "Reporta una persona afectada."},
    {:find_person, "find_person documento | [nombre=..] [zona=..] [estado=..]",
     "Busca personas."},
    {:set_person_state, "set_person_state documento estado", "Cambia el estado de una persona."},
    {:send_family_message, "send_family_message documento \"mensaje\"",
     "Deja un mensaje para una persona."},
    {:list_family_messages, "list_family_messages documento",
     "Lista los mensajes de una persona."},
    {:mark_message_delivered, "mark_message_delivered id", "Marca un mensaje como entregado."},
    {:report_pet, "report_pet tipo especie nombre color tamano zona contacto [caracteristicas]",
     "Reporta una mascota perdida (lost) o encontrada (found)."},
    {:list_pets, "list_pets [especie=..] [zona=..] [estado=..]", "Lista reportes de mascotas."},
    {:match_pets, "match_pets", "Busca coincidencias entre mascotas perdidas y encontradas."},
    {:confirm_pet_match, "confirm_pet_match id_perdida id_encontrada",
     "Confirma una coincidencia y cierra ambos reportes."},
    {:register_shelter, "register_shelter codigo nombre zona capacidad [ocupacion]",
     "Registra un albergue."},
    {:check_shelter, "check_shelter codigo", "Cupos y ocupación de un albergue."},
    {:register_entry, "register_entry codigo documento", "Registra el ingreso a un albergue."},
    {:register_exit, "register_exit codigo documento", "Registra la salida de un albergue."},
    {:shelter_report, "shelter_report [n]", "Albergues con mayor ocupación."},
    {:summary, "summary", "Resumen general del sistema."}
  ]

  # ---------------------------------------------------------------------------
  # Mensajes fijos
  # ---------------------------------------------------------------------------

  @doc "Texto de bienvenida al iniciar la consola."
  def bienvenida do
    "Sistema de coordinación de emergencias.\n" <>
      "Escriba help para ver los comandos o connect usuario contrasena tipo zona para entrar."
  end

  @doc "Aviso de sesión cerrada."
  def sesion_cerrada, do: "Sesión cerrada."

  @doc "Despedida al salir de la consola."
  def despedida, do: "Hasta luego."

  # ---------------------------------------------------------------------------
  # Ayuda
  # ---------------------------------------------------------------------------

  @doc """
  Texto de `help`: los comandos con su sintaxis que puede usar la sesión.

  Sin sesión (`nil`) solo aparecen `connect`, `help` y `exit`. Con un usuario
  conectado aparecen los que `Permisos.permitido?/2` autoriza para su tipo, más
  `exit`.
  """
  def ayuda(sesion) do
    visibles =
      Enum.filter(@comandos, fn {comando, _sintaxis, _detalle} -> visible?(sesion, comando) end)

    ancho =
      visibles
      |> Enum.map(fn {_comando, sintaxis, _detalle} -> String.length(sintaxis) end)
      |> Enum.max()

    lineas =
      Enum.map(visibles, fn {_comando, sintaxis, detalle} ->
        "  " <> String.pad_trailing(sintaxis, ancho) <> "  " <> detalle
      end)

    Enum.join([encabezado_ayuda(sesion) | lineas], "\n")
  end

  defp encabezado_ayuda(%Usuario{tipo: tipo}), do: "Comandos disponibles para #{tipo}:"

  defp encabezado_ayuda(_sesion),
    do: "Comandos disponibles (conéctese con connect para usar el resto):"

  defp visible?(%Usuario{tipo: tipo}, comando),
    do: comando == :exit or Permisos.permitido?(tipo, comando)

  defp visible?(_sesion, comando), do: comando in @sin_sesion

  # ---------------------------------------------------------------------------
  # Resultados
  # ---------------------------------------------------------------------------

  @doc """
  Convierte el resultado de un comando (o un error del parser) en texto.

    * `{:error, razon}`: mensaje en español (ver `@errores`). Una razón que no
      está en el mapa se muestra como `"Error: razon con espacios."`.
    * `:ok`: confirmación genérica.
    * `{:ok, valor}`: el valor como texto (entidades con `to_string/1`, una por
      línea; lista vacía como «No se encontraron resultados.»).
  """
  def a_texto({:error, razon}), do: mensaje_error(razon)
  def a_texto(:ok), do: "Operación realizada."
  def a_texto({:ok, valor}), do: valor_a_texto(valor)
  def a_texto(otro), do: "Resultado inesperado: " <> inspect(otro)

  # --- errores ---------------------------------------------------------------

  defp mensaje_error(razon) when is_atom(razon) do
    case Map.fetch(@errores, razon) do
      {:ok, mensaje} -> mensaje
      :error -> "Error: " <> String.replace(Atom.to_string(razon), "_", " ") <> "."
    end
  end

  defp mensaje_error({:argumentos, [esperados: 0]}), do: "Este comando no recibe argumentos."

  defp mensaje_error({:argumentos, [esperados: 1]}),
    do: "Cantidad de argumentos incorrecta: el comando espera 1 argumento."

  defp mensaje_error({:argumentos, [esperados: n]}),
    do: "Cantidad de argumentos incorrecta: el comando espera #{n} argumentos."

  defp mensaje_error({:valor_invalido, nombre}), do: "Valor inválido para «#{nombre}»."

  defp mensaje_error({:filtro_invalido, clave}),
    do: "Filtro inválido «#{clave}»: use clave=valor con una clave permitida."

  defp mensaje_error(otro), do: "Error: " <> inspect(otro) <> "."

  # --- valores ---------------------------------------------------------------

  defp valor_a_texto(%Usuario{} = usuario), do: "Sesión iniciada: #{usuario}"
  defp valor_a_texto(%Zona{} = zona), do: zona_a_texto(zona)
  defp valor_a_texto(%{recursos_por_categoria: _} = resumen), do: resumen_a_texto(resumen)
  defp valor_a_texto(%{por_sector: _} = estadisticas), do: estadisticas_a_texto(estadisticas)

  defp valor_a_texto(%{necesidad: necesidad, movimientos: movimientos}),
    do: asignacion_a_texto(necesidad, movimientos)

  defp valor_a_texto({%Mascota{} = perdida, %Mascota{} = encontrada}) do
    "Coincidencia confirmada. Ambos reportes quedaron resueltos:\n#{perdida}\n#{encontrada}"
  end

  defp valor_a_texto([]), do: "No se encontraron resultados."

  defp valor_a_texto(lista) when is_list(lista),
    do: Enum.map_join(lista, "\n", &elemento_a_texto/1)

  defp valor_a_texto(otro), do: texto_de(otro)

  defp elemento_a_texto(%{perdida_id: perdida, encontrada_id: encontrada, puntaje: puntaje}),
    do: "#{perdida} <-> #{encontrada} (puntaje: #{puntaje})"

  defp elemento_a_texto(%{
         zona: zona,
         categoria: categoria,
         disponible: disponible,
         demanda: demanda,
         deficit: deficit
       }) do
    "#{zona} / #{categoria}: disponible #{disponible}, demanda #{demanda}, déficit #{deficit}"
  end

  defp elemento_a_texto(otro), do: texto_de(otro)

  # `to_string/1` solo si el valor lo soporta; si no, `inspect/1` (nunca falla).
  defp texto_de(valor) when is_binary(valor), do: valor

  defp texto_de(valor) when is_list(valor), do: inspect(valor)

  defp texto_de(valor) do
    if String.Chars.impl_for(valor), do: to_string(valor), else: inspect(valor)
  end

  # --- zonas -----------------------------------------------------------------

  defp zona_a_texto(%Zona{} = zona) do
    nodos = zona |> Zona.aplanar() |> Enum.map(&nodo_a_texto/1)
    Enum.join([to_string(zona) | nodos], "\n")
  end

  defp nodo_a_texto({:sector, codigo, nombre, personas}),
    do: "  Sector #{codigo} - #{nombre}: #{personas} personas"

  defp nodo_a_texto({:punto, codigo, nombre, personas}),
    do: "    Punto #{codigo} - #{nombre}: #{personas} personas"

  defp estadisticas_a_texto(estadisticas) do
    por_sector =
      Enum.map(estadisticas.por_sector, fn %{codigo: codigo, total: total} ->
        "    Sector #{codigo}: #{total} personas"
      end)

    Enum.join(
      [
        "Estadísticas de la zona:",
        "  Personas en sectores y puntos: #{estadisticas.total_personas}",
        "  Personas estimadas de la zona: #{estadisticas.estimadas}",
        "  Sectores: #{estadisticas.num_sectores}",
        "  Puntos de atención: #{estadisticas.num_puntos}"
        | por_sector
      ],
      "\n"
    )
  end

  # --- asignación ------------------------------------------------------------

  defp asignacion_a_texto(necesidad, movimientos) when is_list(movimientos) do
    "Asignación registrada (#{length(movimientos)} movimiento(s) de inventario).\n#{necesidad}"
  end

  defp asignacion_a_texto(necesidad, _movimientos), do: "Asignación registrada.\n#{necesidad}"

  # --- resumen por secciones -------------------------------------------------

  defp resumen_a_texto(resumen) do
    recursos =
      for categoria <- Recurso.categorias() do
        "#{categoria}: #{Map.get(resumen.recursos_por_categoria, categoria, 0)}"
      end

    necesidades =
      for prioridad <- @prioridades do
        "#{prioridad}: #{Map.get(resumen.necesidades_pendientes, prioridad, 0)}"
      end

    Enum.join(
      [
        seccion("Recursos disponibles", recursos),
        seccion("Necesidades pendientes", necesidades),
        seccion("Personas", ["Personas localizadas: #{resumen.personas_localizadas}"]),
        seccion("Mensajes", [
          "Total: #{resumen.mensajes.total}",
          "Pendientes: #{resumen.mensajes.pendientes}"
        ]),
        seccion("Mascotas", [
          "Activas: #{resumen.mascotas.activas}",
          "Posibles coincidencias: #{resumen.mascotas.posibles}",
          "Resueltas: #{resumen.mascotas.resueltas}"
        ]),
        seccion("Albergues", [
          "Capacidad total: #{resumen.albergues.capacidad_total}",
          "Ocupación total: #{resumen.albergues.ocupacion_total}"
        ]),
        seccion("Zonas", zonas_del_resumen(resumen.zonas))
      ],
      "\n\n"
    )
  end

  defp zonas_del_resumen([]), do: ["No hay zonas registradas."]

  defp zonas_del_resumen(zonas) do
    Enum.map(zonas, fn zona ->
      "[#{zona.codigo}] #{zona.nombre} (#{zona.nivel}): #{zona.personas} personas"
    end)
  end

  defp seccion(titulo, lineas) do
    Enum.join(["=== #{titulo} ===" | Enum.map(lineas, fn linea -> "  " <> linea end)], "\n")
  end
end
