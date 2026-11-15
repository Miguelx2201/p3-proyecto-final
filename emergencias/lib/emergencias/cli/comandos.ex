defmodule Emergencias.CLI.Comandos do
  @moduledoc """
  Ejecuta un comando de la consola llamando a la fachada `Emergencias`.

  `ejecutar(sesion, comando, argumentos)` recibe:

    * `sesion`: `nil` (nadie conectado) o el `Usuario` conectado.
    * `comando`: átomo del comando (por ejemplo `:register_zone`).
    * `argumentos`: lista de valores **ya convertidos** por `Emergencias.CLI.Parser`.
      En los comandos con filtros es la keyword list de filtros.

  Devuelve lo mismo que la fachada: `:ok`, `{:ok, valor}` o `{:error, razon}`.
  Ninguna función lanza excepciones.

  ## Comandos de este módulo

    * `:connect` - `[usuario, contrasena, tipo, zona]`
    * `:disconnect` - `[]`
    * `:register_zone` - `[codigo, nombre, nivel]`
    * `:register_sector` - `[zona, codigo, nombre, personas]`
    * `:register_point` - `[zona, sector, codigo, nombre, personas]`
    * `:zone_status` - `[zona]`
    * `:zone_stats` - `[zona]`
    * `:register_need` - `[tipo, cantidad, prioridad, zona, descripcion]`
    * `:list_needs` - filtros opcionales `zona:`, `tipo:`, `prioridad:`, `estado:`
    * `:pending_needs` - `[]`
    * `:set_need_status` - `[id, estado]`
    * `:cancel_need` - `[id]`
    * `:assign_resource` - `[id_necesidad, categoria, cantidad]`
    * `:register_resource` - `[id, categoria, cantidad, unidad, ubicacion]` o
      `[id, categoria, cantidad, unidad, ubicacion, zona]` (sin zona se usa la
      zona principal del usuario)
    * `:list_resources` - filtros opcionales `categoria:`, `zona:`
    * `:add_stock` - `[id, cantidad]`
    * `:remove_stock` - `[id, cantidad]`
    * `:transfer_resource` - `[id, centro_origen, centro_destino, cantidad]`
    * `:critical_resources` - `[]`
    * `:report_person` - `[documento, nombre, edad, zona, estado]`
    * `:find_person` - `[documento]` o filtros opcionales `nombre:`, `zona:`, `estado:`
    * `:set_person_state` - `[documento, estado]`
    * `:send_family_message` - `[documento, mensaje]`
    * `:list_family_messages` - `[documento]`
    * `:mark_message_delivered` - `[id]`
    * `:report_pet` - `[tipo, especie, nombre, color, tamano, zona, contacto]` o
      `[tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas]`
    * `:list_pets` - filtros opcionales `especie:`, `zona:`, `estado:`
    * `:match_pets` - `[]`
    * `:confirm_pet_match` - `[id_perdida, id_encontrada]`
    * `:register_shelter` - `[codigo, nombre, zona, capacidad]` o
      `[codigo, nombre, zona, capacidad, ocupacion]`
    * `:check_shelter` - `[codigo]`
    * `:register_entry` - `[codigo, documento]`
    * `:register_exit` - `[codigo, documento]`
    * `:shelter_report` - `[]` o `[n]`
    * `:summary` - `[]`

  ## Errores propios

    * `{:error, {:argumentos, esperados: n}}`: cantidad de argumentos incorrecta
      (en los comandos con argumentos opcionales, como `:register_resource`
      que admite 5 o 6, `n` es el mínimo: 5).
    * `{:error, :valor_invalido}`: los argumentos no son una lista, o los filtros
      de un comando con filtros no son una keyword list. En `:find_person`
      también cuando no es ni un único documento ni una keyword list.
    * `{:error, :no_conectado}`: comando que exige sesión y `sesion` es `nil`.
    * `{:error, :ya_conectado}`: `connect` con una sesión ya iniciada.
    * `{:error, :no_implementado}`: comando que todavía no tiene cláusula aquí.
  """

  alias Emergencias.Dominio.Usuario

  # Comando => argumentos que espera:
  #
  #   * entero: cantidad exacta de argumentos posicionales;
  #   * rango: cantidad mínima..máxima (argumentos opcionales al final);
  #   * `:filtros`: una keyword list (puede estar vacía);
  #   * `:documento_o_filtros`: un único documento (texto) o una keyword list.
  @aridad %{
    connect: 4,
    disconnect: 0,
    register_zone: 3,
    register_sector: 4,
    register_point: 5,
    zone_status: 1,
    zone_stats: 1,
    register_need: 5,
    list_needs: :filtros,
    pending_needs: 0,
    set_need_status: 2,
    cancel_need: 1,
    assign_resource: 3,
    register_resource: 5..6,
    list_resources: :filtros,
    add_stock: 2,
    remove_stock: 2,
    transfer_resource: 4,
    critical_resources: 0,
    report_person: 5,
    find_person: :documento_o_filtros,
    set_person_state: 2,
    send_family_message: 2,
    list_family_messages: 1,
    mark_message_delivered: 1,
    report_pet: 7..8,
    list_pets: :filtros,
    match_pets: 0,
    confirm_pet_match: 2,
    register_shelter: 4..5,
    check_shelter: 1,
    register_entry: 2,
    register_exit: 2,
    shelter_report: 0..1,
    summary: 0
  }

  @doc "Ejecuta `comando` con `argumentos` en nombre de `sesion`."
  def ejecutar(sesion, comando, argumentos) when is_list(argumentos) do
    case Map.fetch(@aridad, comando) do
      {:ok, :filtros} ->
        if Keyword.keyword?(argumentos),
          do: despachar(sesion, comando, argumentos),
          else: {:error, :valor_invalido}

      {:ok, :documento_o_filtros} ->
        if documento_o_filtros?(argumentos),
          do: despachar(sesion, comando, argumentos),
          else: {:error, :valor_invalido}

      {:ok, esperados} ->
        if cantidad_valida?(length(argumentos), esperados),
          do: despachar(sesion, comando, argumentos),
          else: {:error, {:argumentos, esperados: minimo(esperados)}}

      :error ->
        {:error, :no_implementado}
    end
  end

  def ejecutar(_sesion, _comando, _argumentos), do: {:error, :valor_invalido}

  defp documento_o_filtros?([documento]) when is_binary(documento), do: true
  defp documento_o_filtros?(argumentos), do: Keyword.keyword?(argumentos)

  defp cantidad_valida?(cantidad, esperados) when is_integer(esperados),
    do: cantidad == esperados

  defp cantidad_valida?(cantidad, %Range{} = esperados), do: cantidad in esperados

  defp minimo(esperados) when is_integer(esperados), do: esperados
  defp minimo(%Range{first: primero}), do: primero

  # --- sesión ----------------------------------------------------------------

  defp despachar(nil, :connect, [username, password, tipo, zona]),
    do: Emergencias.connect(username, password, tipo, zona)

  defp despachar(%Usuario{}, :connect, _argumentos), do: {:error, :ya_conectado}

  # Todo lo demás exige sesión.
  defp despachar(nil, _comando, _argumentos), do: {:error, :no_conectado}

  defp despachar(%Usuario{} = usuario, :disconnect, []), do: Emergencias.disconnect(usuario)

  # --- zonas -----------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :register_zone, [codigo, nombre, nivel]),
    do: Emergencias.register_zone(usuario, codigo, nombre, nivel)

  defp despachar(%Usuario{} = usuario, :register_sector, [zona, codigo, nombre, personas]),
    do: Emergencias.register_sector(usuario, zona, codigo, nombre, personas)

  defp despachar(%Usuario{} = usuario, :register_point, [zona, sector, codigo, nombre, personas]),
    do: Emergencias.register_point(usuario, zona, sector, codigo, nombre, personas)

  defp despachar(%Usuario{} = usuario, :zone_status, [zona]),
    do: Emergencias.zone_status(usuario, zona)

  defp despachar(%Usuario{} = usuario, :zone_stats, [zona]),
    do: Emergencias.zone_stats(usuario, zona)

  # --- necesidades -----------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :register_need, [
         tipo,
         cantidad,
         prioridad,
         zona,
         descripcion
       ]),
       do: Emergencias.register_need(usuario, tipo, cantidad, prioridad, zona, descripcion)

  defp despachar(%Usuario{} = usuario, :list_needs, filtros),
    do: Emergencias.list_needs(usuario, filtros)

  defp despachar(%Usuario{} = usuario, :pending_needs, []),
    do: Emergencias.pending_needs(usuario)

  defp despachar(%Usuario{} = usuario, :set_need_status, [id, estado]),
    do: Emergencias.set_need_status(usuario, id, estado)

  defp despachar(%Usuario{} = usuario, :cancel_need, [id]),
    do: Emergencias.cancel_need(usuario, id)

  defp despachar(%Usuario{} = usuario, :assign_resource, [id, categoria, cantidad]),
    do: Emergencias.assign_resource(usuario, id, categoria, cantidad)

  # --- recursos --------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :register_resource, [
         id,
         categoria,
         cantidad,
         unidad,
         ubicacion
       ]),
       do: Emergencias.register_resource(usuario, id, categoria, cantidad, unidad, ubicacion)

  defp despachar(%Usuario{} = usuario, :register_resource, [
         id,
         categoria,
         cantidad,
         unidad,
         ubicacion,
         zona
       ]),
       do:
         Emergencias.register_resource(
           usuario,
           id,
           categoria,
           cantidad,
           unidad,
           ubicacion,
           zona
         )

  defp despachar(%Usuario{} = usuario, :list_resources, filtros),
    do: Emergencias.list_resources(usuario, filtros)

  defp despachar(%Usuario{} = usuario, :add_stock, [id, cantidad]),
    do: Emergencias.add_stock(usuario, id, cantidad)

  defp despachar(%Usuario{} = usuario, :remove_stock, [id, cantidad]),
    do: Emergencias.remove_stock(usuario, id, cantidad)

  defp despachar(%Usuario{} = usuario, :transfer_resource, [
         id,
         centro_origen,
         centro_destino,
         cantidad
       ]),
       do: Emergencias.transfer_resource(usuario, id, centro_origen, centro_destino, cantidad)

  defp despachar(%Usuario{} = usuario, :critical_resources, []),
    do: Emergencias.critical_resources(usuario)

  # --- personas y mensajes ---------------------------------------------------

  defp despachar(%Usuario{} = usuario, :report_person, [documento, nombre, edad, zona, estado]),
    do: Emergencias.report_person(usuario, documento, nombre, edad, zona, estado)

  defp despachar(%Usuario{} = usuario, :find_person, [documento]) when is_binary(documento),
    do: Emergencias.find_person(usuario, documento)

  defp despachar(%Usuario{} = usuario, :find_person, filtros),
    do: Emergencias.find_person(usuario, filtros)

  defp despachar(%Usuario{} = usuario, :set_person_state, [documento, estado]),
    do: Emergencias.set_person_state(usuario, documento, estado)

  defp despachar(%Usuario{} = usuario, :send_family_message, [documento, mensaje]),
    do: Emergencias.send_family_message(usuario, documento, mensaje)

  defp despachar(%Usuario{} = usuario, :list_family_messages, [documento]),
    do: Emergencias.list_family_messages(usuario, documento)

  defp despachar(%Usuario{} = usuario, :mark_message_delivered, [id]),
    do: Emergencias.mark_message_delivered(usuario, id)

  # --- mascotas --------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :report_pet, [
         tipo,
         especie,
         nombre,
         color,
         tamano,
         zona,
         contacto
       ]),
       do: Emergencias.report_pet(usuario, tipo, especie, nombre, color, tamano, zona, contacto)

  defp despachar(%Usuario{} = usuario, :report_pet, [
         tipo,
         especie,
         nombre,
         color,
         tamano,
         zona,
         contacto,
         caracteristicas
       ]),
       do:
         Emergencias.report_pet(
           usuario,
           tipo,
           especie,
           nombre,
           color,
           tamano,
           zona,
           contacto,
           caracteristicas
         )

  defp despachar(%Usuario{} = usuario, :list_pets, filtros),
    do: Emergencias.list_pets(usuario, filtros)

  defp despachar(%Usuario{} = usuario, :match_pets, []),
    do: Emergencias.match_pets(usuario)

  defp despachar(%Usuario{} = usuario, :confirm_pet_match, [id_perdida, id_encontrada]),
    do: Emergencias.confirm_pet_match(usuario, id_perdida, id_encontrada)

  # --- albergues -------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :register_shelter, [codigo, nombre, zona, capacidad]),
    do: Emergencias.register_shelter(usuario, codigo, nombre, zona, capacidad)

  defp despachar(%Usuario{} = usuario, :register_shelter, [
         codigo,
         nombre,
         zona,
         capacidad,
         ocupacion
       ]),
       do: Emergencias.register_shelter(usuario, codigo, nombre, zona, capacidad, ocupacion)

  defp despachar(%Usuario{} = usuario, :check_shelter, [codigo]),
    do: Emergencias.check_shelter(usuario, codigo)

  defp despachar(%Usuario{} = usuario, :register_entry, [codigo, documento]),
    do: Emergencias.register_entry(usuario, codigo, documento)

  defp despachar(%Usuario{} = usuario, :register_exit, [codigo, documento]),
    do: Emergencias.register_exit(usuario, codigo, documento)

  defp despachar(%Usuario{} = usuario, :shelter_report, []),
    do: Emergencias.shelter_report(usuario)

  defp despachar(%Usuario{} = usuario, :shelter_report, [n]),
    do: Emergencias.shelter_report(usuario, n)

  # --- resumen ---------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :summary, []),
    do: Emergencias.summary(usuario)

  defp despachar(_otra_sesion, _comando, _argumentos), do: {:error, :usuario_invalido}
end
