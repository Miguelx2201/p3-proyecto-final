defmodule Emergencias.Servicios.Permisos do
  @moduledoc """
  Restringe las operaciones según el tipo de usuario.

  Los permisos viven en un mapa `comando => roles permitidos`. Cambiar un
  permiso es editar una línea de ese mapa. Ninguna función lanza excepciones.

  Los comandos se identifican con átomos (por ejemplo `:assign_resource`) y los
  tipos de usuario son los de `Emergencias.Dominio.Usuario.tipos/0`.
  """

  alias Emergencias.Dominio.Usuario

  @todos Usuario.tipos()
  @voluntario_o_superior [:voluntario, :coordinador, :administrador]
  @coordinador_o_superior [:coordinador, :administrador]

  @permisos %{
    # Todos los usuarios
    connect: @todos,
    disconnect: @todos,
    help: @todos,
    register_need: @todos,
    list_needs: @todos,
    pending_needs: @todos,
    report_person: @todos,
    find_person: @todos,
    send_family_message: @todos,
    list_family_messages: @todos,
    report_pet: @todos,
    list_pets: @todos,
    zone_status: @todos,
    check_shelter: @todos,
    # Voluntario, coordinador y administrador
    set_person_state: @voluntario_o_superior,
    mark_message_delivered: @voluntario_o_superior,
    match_pets: @voluntario_o_superior,
    confirm_pet_match: @voluntario_o_superior,
    register_entry: @voluntario_o_superior,
    register_exit: @voluntario_o_superior,
    list_resources: @voluntario_o_superior,
    # Coordinador y administrador
    register_zone: @coordinador_o_superior,
    register_sector: @coordinador_o_superior,
    register_point: @coordinador_o_superior,
    zone_stats: @coordinador_o_superior,
    register_resource: @coordinador_o_superior,
    add_stock: @coordinador_o_superior,
    remove_stock: @coordinador_o_superior,
    transfer_resource: @coordinador_o_superior,
    assign_resource: @coordinador_o_superior,
    set_need_status: @coordinador_o_superior,
    cancel_need: @coordinador_o_superior,
    register_shelter: @coordinador_o_superior,
    shelter_report: @coordinador_o_superior,
    critical_resources: @coordinador_o_superior,
    summary: @coordinador_o_superior
  }

  @doc """
  Verdadero si el tipo de usuario puede ejecutar el comando.

  Un comando inexistente o un tipo desconocido dan `false`.
  """
  def permitido?(tipo, comando) do
    case Map.fetch(@permisos, comando) do
      {:ok, roles} -> tipo in roles
      :error -> false
    end
  end

  @doc """
  Verifica el permiso. Devuelve `:ok`, `{:error, :permiso_denegado}` o
  `{:error, :comando_desconocido}`.

  El comando se revisa primero: con un comando inexistente la respuesta es
  siempre `:comando_desconocido`, sin importar el tipo.
  """
  def verificar(tipo, comando) do
    case Map.fetch(@permisos, comando) do
      :error -> {:error, :comando_desconocido}
      {:ok, roles} -> if tipo in roles, do: :ok, else: {:error, :permiso_denegado}
    end
  end
end
