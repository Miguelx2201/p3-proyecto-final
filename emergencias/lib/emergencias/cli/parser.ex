defmodule Emergencias.CLI.Parser do
  @moduledoc """
  Convierte una línea de texto en un comando válido con sus argumentos ya
  convertidos. No ejecuta nada.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o
  `{:error, razon}`.

  La línea se separa con `OptionParser.split/1` (divide por espacios y respeta
  las comillas). El primer token es el comando y el resto son sus argumentos.

  ## Tipos de argumento

    * `:texto`: texto libre, sanitizado con `Emergencias.Util.sanitizar_texto/1`.
      No puede quedar vacío.
    * `:entero`: entero no negativo (`Emergencias.Util.parsear_entero_no_negativo/1`).
    * `:tipo_necesidad` y `:categoria`: uno de los valores permitidos o
      `otra:texto`, que se convierte en `{:otra, "texto"}` (el texto va en
      `tipo_otro`).
    * `:prioridad` y `:nivel`: enumeraciones que aceptan `critica` y `critico`
      indistintamente.
    * `:tipo_usuario`, `:estado_necesidad`, `:estado_persona`, `:estado_mascota`
      y `:tamano`: enumeraciones (`Emergencias.Util.parsear_enum/2`).
    * `:tipo_mascota`: `lost` o `perdida` dan `:perdida`; `found` o `encontrada`
      dan `:encontrada`.

  ## Argumentos opcionales

  Algunos comandos admiten argumentos opcionales al final (`report_pet`,
  `register_resource`, `register_shelter` y `shelter_report`). Y `find_person`
  acepta un único documento o filtros `clave=valor`.

  ## Errores

    * `{:error, :linea_vacia}`
    * `{:error, :comando_desconocido}`
    * `{:error, {:argumentos, esperados: n}}` (en los comandos con argumentos
      opcionales, `n` es la cantidad mínima)
    * `{:error, {:valor_invalido, nombre_argumento}}`
    * `{:error, {:filtro_invalido, clave}}`
  """

  alias Emergencias.Util

  # Valores permitidos de cada enumeración (átomos sin tildes ni eñes).
  @enumeraciones %{
    tipo_usuario: [:administrador, :coordinador, :voluntario, :ciudadano],
    nivel: [:critico, :alto, :medio, :bajo],
    prioridad: [:critica, :alta, :media, :baja],
    categoria: [
      :agua,
      :alimentos,
      :medicamentos,
      :primeros_auxilios,
      :refugio,
      :transporte,
      :rescate,
      :otra
    ],
    estado_necesidad: [:pendiente, :asignada, :en_atencion, :atendida, :cancelada],
    estado_persona: [
      :sin_informacion,
      :reportada,
      :localizada,
      :trasladada,
      :en_albergue,
      :reunificada
    ],
    estado_mascota: [:activa, :posible_coincidencia, :resuelta],
    tamano: [:pequeno, :mediano, :grande]
  }

  # Tabla de comandos: nombre escrito por el usuario => {comando, especificación}.
  #
  #   * Lista de `{nombre_argumento, tipo}`: argumentos posicionales.
  #   * `{:filtros, [{clave, tipo}]}`: filtros `clave=valor`; las claves de la
  #     lista son las únicas permitidas.
  #   * `{:opcionales, requeridos, opcionales}`: argumentos posicionales; los
  #     opcionales van al final y pueden omitirse.
  #   * `{:documento_o_filtros, [{clave, tipo}]}`: un único documento o filtros.
  @comandos %{
    "help" => {:help, []},
    "exit" => {:exit, []},
    "connect" =>
      {:connect, [usuario: :texto, contrasena: :texto, tipo: :tipo_usuario, zona: :texto]},
    "disconnect" => {:disconnect, []},
    "register_zone" => {:register_zone, [codigo: :texto, nombre: :texto, nivel: :nivel]},
    "register_sector" =>
      {:register_sector, [zona: :texto, codigo: :texto, nombre: :texto, personas: :entero]},
    "register_point" =>
      {:register_point,
       [
         zona: :texto,
         sector: :texto,
         codigo: :texto,
         nombre: :texto,
         personas: :entero
       ]},
    "zone_status" => {:zone_status, [zona: :texto]},
    "zone_stats" => {:zone_stats, [zona: :texto]},
    "register_need" =>
      {:register_need,
       [
         tipo: :tipo_necesidad,
         cantidad: :entero,
         prioridad: :prioridad,
         zona: :texto,
         descripcion: :texto
       ]},
    "pending_needs" => {:pending_needs, []},
    "set_need_status" => {:set_need_status, [id: :texto, estado: :estado_necesidad]},
    "cancel_need" => {:cancel_need, [id: :texto]},
    "assign_resource" =>
      {:assign_resource, [id: :texto, categoria: :categoria, cantidad: :entero]},
    "register_resource" =>
      {:register_resource,
       {:opcionales,
        [id: :texto, categoria: :categoria, cantidad: :entero, unidad: :texto, ubicacion: :texto],
        [zona: :texto]}},
    "add_stock" => {:add_stock, [id: :texto, cantidad: :entero]},
    "remove_stock" => {:remove_stock, [id: :texto, cantidad: :entero]},
    "transfer_resource" =>
      {:transfer_resource,
       [id: :texto, centro_origen: :texto, centro_destino: :texto, cantidad: :entero]},
    "critical_resources" => {:critical_resources, []},
    "report_person" =>
      {:report_person,
       [
         documento: :texto,
         nombre: :texto,
         edad: :entero,
         zona: :texto,
         estado: :estado_persona
       ]},
    "set_person_state" => {:set_person_state, [documento: :texto, estado: :estado_persona]},
    "send_family_message" => {:send_family_message, [documento: :texto, mensaje: :texto]},
    "list_family_messages" => {:list_family_messages, [documento: :texto]},
    "mark_message_delivered" => {:mark_message_delivered, [id: :texto]},
    "report_pet" =>
      {:report_pet,
       {:opcionales,
        [
          tipo: :tipo_mascota,
          especie: :texto,
          nombre: :texto,
          color: :texto,
          tamano: :tamano,
          zona: :texto,
          contacto: :texto
        ], [caracteristicas: :texto]}},
    "match_pets" => {:match_pets, []},
    "confirm_pet_match" => {:confirm_pet_match, [id_perdida: :texto, id_encontrada: :texto]},
    "register_shelter" =>
      {:register_shelter,
       {:opcionales, [codigo: :texto, nombre: :texto, zona: :texto, capacidad: :entero],
        [ocupacion: :entero]}},
    "check_shelter" => {:check_shelter, [codigo: :texto]},
    "register_entry" => {:register_entry, [codigo: :texto, documento: :texto]},
    "register_exit" => {:register_exit, [codigo: :texto, documento: :texto]},
    "shelter_report" => {:shelter_report, {:opcionales, [], [n: :entero]}},
    "summary" => {:summary, []},
    "list_needs" =>
      {:list_needs,
       {:filtros,
        [
          zona: :texto,
          tipo: :tipo_necesidad,
          prioridad: :prioridad,
          estado: :estado_necesidad
        ]}},
    "list_resources" => {:list_resources, {:filtros, [zona: :texto, categoria: :categoria]}},
    "list_pets" =>
      {:list_pets, {:filtros, [zona: :texto, especie: :texto, estado: :estado_mascota]}},
    "find_person" =>
      {:find_person,
       {:documento_o_filtros, [nombre: :texto, zona: :texto, estado: :estado_persona]}}
  }

  @doc """
  Convierte una línea de texto en `{:ok, {comando, argumentos}}`.

  `comando` es un átomo (por ejemplo `:register_need`) y `argumentos` la lista
  de valores ya convertidos. En los comandos con filtros, `argumentos` es la
  keyword list de filtros.

  Acepta saltos de línea de Windows (`\\r\\n`) al final de la línea.
  """
  def parsear(linea) when is_binary(linea) do
    case OptionParser.split(String.trim(linea)) do
      [] -> {:error, :linea_vacia}
      [nombre | tokens] -> parsear_comando(nombre, tokens)
    end
  end

  def parsear(_otro), do: {:error, :linea_vacia}

  defp parsear_comando(nombre, tokens) do
    clave = nombre |> String.trim() |> String.downcase()

    case Map.fetch(@comandos, clave) do
      {:ok, {comando, {:filtros, permitidos}}} ->
        with {:ok, filtros} <- parsear_filtros(tokens, permitidos) do
          {:ok, {comando, filtros}}
        end

      {:ok, {comando, {:documento_o_filtros, permitidos}}} ->
        parsear_documento_o_filtros(comando, tokens, permitidos)

      {:ok, {comando, {:opcionales, requeridos, opcionales}}} ->
        parsear_argumentos(comando, requeridos, opcionales, tokens)

      {:ok, {comando, esperados}} ->
        parsear_argumentos(comando, esperados, [], tokens)

      :error ->
        {:error, :comando_desconocido}
    end
  end

  # Con opcionales se acepta de `length(requeridos)` a `length(requeridos ++ opcionales)`
  # tokens; el error informa la cantidad mínima.
  defp parsear_argumentos(comando, requeridos, opcionales, tokens) do
    minimo = length(requeridos)
    maximo = minimo + length(opcionales)

    if length(tokens) in minimo..maximo//1 do
      esperados = Enum.take(requeridos ++ opcionales, length(tokens))

      with {:ok, valores} <- convertir_argumentos(esperados, tokens, []) do
        {:ok, {comando, valores}}
      end
    else
      {:error, {:argumentos, esperados: minimo}}
    end
  end

  # Un único token sin `=` es un documento; en cualquier otro caso son filtros.
  defp parsear_documento_o_filtros(comando, [token], permitidos) do
    if String.contains?(token, "=") do
      parsear_filtros_de(comando, [token], permitidos)
    else
      case convertir(token, :texto) do
        {:ok, documento} -> {:ok, {comando, [documento]}}
        {:error, _razon} -> {:error, {:valor_invalido, :documento}}
      end
    end
  end

  defp parsear_documento_o_filtros(comando, tokens, permitidos),
    do: parsear_filtros_de(comando, tokens, permitidos)

  defp parsear_filtros_de(comando, tokens, permitidos) do
    with {:ok, filtros} <- parsear_filtros(tokens, permitidos) do
      {:ok, {comando, filtros}}
    end
  end

  # Recursiva con acumulador: se detiene en el primer argumento inválido.
  defp convertir_argumentos([], [], acumulado), do: {:ok, Enum.reverse(acumulado)}

  defp convertir_argumentos([{nombre, tipo} | esperados], [token | resto], acumulado) do
    case convertir(token, tipo) do
      {:ok, valor} -> convertir_argumentos(esperados, resto, [valor | acumulado])
      {:error, _razon} -> {:error, {:valor_invalido, nombre}}
    end
  end

  @doc """
  Convierte los tokens `clave=valor` en una keyword list.

  `permitidos` es una keyword list `clave: tipo` con las únicas claves aceptadas
  y el tipo de su valor. Devuelve `{:ok, keyword}` respetando el orden de los
  tokens.

    * Clave desconocida, repetida o token sin `=`: `{:error, {:filtro_invalido, clave}}`.
    * Valor que no se puede convertir: `{:error, {:valor_invalido, clave}}`.

  Nunca crea átomos a partir del texto: busca la clave entre las permitidas.
  """
  def parsear_filtros(tokens, permitidos) when is_list(tokens) and is_list(permitidos) do
    parsear_filtros(tokens, permitidos, [])
  end

  def parsear_filtros(_tokens, _permitidos), do: {:error, :filtros_invalidos}

  defp parsear_filtros([], _permitidos, acumulado), do: {:ok, Enum.reverse(acumulado)}

  defp parsear_filtros([token | resto], permitidos, acumulado) do
    with {:ok, clave, valor} <- separar_filtro(token),
         {:ok, {atomo, tipo}} <- buscar_clave(clave, permitidos, acumulado),
         {:ok, convertido} <- convertir_filtro(atomo, valor, tipo) do
      parsear_filtros(resto, permitidos, [{atomo, convertido} | acumulado])
    end
  end

  defp separar_filtro(token) do
    case String.split(token, "=", parts: 2) do
      [clave, valor] -> {:ok, clave |> String.trim() |> String.downcase(), valor}
      [_sin_igual] -> {:error, {:filtro_invalido, token}}
    end
  end

  defp buscar_clave(clave, permitidos, acumulado) do
    case Enum.find(permitidos, fn {atomo, _tipo} -> Atom.to_string(atomo) == clave end) do
      nil ->
        {:error, {:filtro_invalido, clave}}

      {atomo, _tipo} = encontrado ->
        if Keyword.has_key?(acumulado, atomo) do
          {:error, {:filtro_invalido, clave}}
        else
          {:ok, encontrado}
        end
    end
  end

  defp convertir_filtro(atomo, valor, tipo) do
    case convertir(valor, tipo) do
      {:ok, convertido} -> {:ok, convertido}
      {:error, _razon} -> {:error, {:valor_invalido, atomo}}
    end
  end

  @doc """
  Convierte un texto al `tipo` indicado (ver el módulo para la lista de tipos).

  Devuelve `{:ok, valor}` o `{:error, :valor_invalido}`; si `tipo` no existe,
  `{:error, :tipo_invalido}`.
  """
  def convertir(texto, _tipo) when not is_binary(texto), do: {:error, :valor_invalido}

  def convertir(texto, :texto) do
    case Util.sanitizar_texto(texto) do
      "" -> {:error, :valor_invalido}
      limpio -> {:ok, limpio}
    end
  end

  def convertir(texto, :entero) do
    case Util.parsear_entero_no_negativo(texto) do
      {:ok, numero} -> {:ok, numero}
      {:error, _razon} -> {:error, :valor_invalido}
    end
  end

  def convertir(texto, :prioridad) do
    Util.parsear_enum(unificar_critico(texto, "critica"), @enumeraciones.prioridad)
  end

  def convertir(texto, :nivel) do
    Util.parsear_enum(unificar_critico(texto, "critico"), @enumeraciones.nivel)
  end

  def convertir(texto, tipo) when tipo in [:tipo_necesidad, :categoria] do
    case String.split(texto, ":", parts: 2) do
      [prefijo, detalle] -> convertir_otra(prefijo, detalle)
      [_sin_dos_puntos] -> Util.parsear_enum(texto, @enumeraciones.categoria -- [:otra])
    end
  end

  def convertir(texto, :tipo_mascota) do
    case texto |> String.trim() |> String.downcase() do
      palabra when palabra in ["lost", "perdida"] -> {:ok, :perdida}
      palabra when palabra in ["found", "encontrada"] -> {:ok, :encontrada}
      _otra -> {:error, :valor_invalido}
    end
  end

  def convertir(texto, tipo) do
    case Map.fetch(@enumeraciones, tipo) do
      {:ok, permitidos} -> Util.parsear_enum(texto, permitidos)
      :error -> {:error, :tipo_invalido}
    end
  end

  # `critica` y `critico` significan lo mismo: se lleva al valor de la enumeración.
  defp unificar_critico(texto, canonico) do
    case texto |> String.trim() |> String.downcase() do
      palabra when palabra in ["critica", "critico"] -> canonico
      otra -> otra
    end
  end

  # `otra:texto` -> {:otra, "texto"}. El texto puede contener más `:`.
  defp convertir_otra(prefijo, detalle) do
    with "otra" <- prefijo |> String.trim() |> String.downcase(),
         {:ok, texto} <- convertir(detalle, :texto) do
      {:ok, {:otra, texto}}
    else
      _ -> {:error, :valor_invalido}
    end
  end
end
