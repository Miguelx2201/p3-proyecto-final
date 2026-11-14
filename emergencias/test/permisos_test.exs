defmodule Emergencias.Servicios.PermisosTest do
  use ExUnit.Case, async: true

  alias Emergencias.Servicios.Permisos

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]

  @para_todos ~w(connect disconnect help register_need list_needs pending_needs
    report_person find_person send_family_message list_family_messages
    report_pet list_pets zone_status check_shelter)a

  @voluntario_o_superior ~w(set_person_state mark_message_delivered match_pets
    confirm_pet_match register_entry register_exit list_resources)a

  @coordinador_o_superior ~w(register_zone register_sector register_point
    zone_stats register_resource add_stock remove_stock transfer_resource
    assign_resource set_need_status cancel_need register_shelter
    shelter_report critical_resources summary)a

  describe "casos pedidos por el issue" do
    test "un ciudadano no puede assign_resource" do
      refute Permisos.permitido?(:ciudadano, :assign_resource)
      assert Permisos.verificar(:ciudadano, :assign_resource) == {:error, :permiso_denegado}
    end

    test "un coordinador sí puede assign_resource" do
      assert Permisos.permitido?(:coordinador, :assign_resource)
      assert Permisos.verificar(:coordinador, :assign_resource) == :ok
    end

    test "un comando inexistente devuelve :comando_desconocido" do
      refute Permisos.permitido?(:coordinador, :comando_inexistente)

      assert Permisos.verificar(:coordinador, :comando_inexistente) ==
               {:error, :comando_desconocido}
    end
  end

  describe "comandos para todos" do
    for tipo <- @tipos, comando <- @para_todos do
      test "#{tipo} puede #{comando}" do
        assert Permisos.permitido?(unquote(tipo), unquote(comando))
        assert Permisos.verificar(unquote(tipo), unquote(comando)) == :ok
      end
    end
  end

  describe "comandos de voluntario o superior" do
    for comando <- @voluntario_o_superior do
      test "ciudadano no puede #{comando}" do
        refute Permisos.permitido?(:ciudadano, unquote(comando))

        assert Permisos.verificar(:ciudadano, unquote(comando)) == {:error, :permiso_denegado}
      end

      for tipo <- [:voluntario, :coordinador, :administrador] do
        test "#{tipo} puede #{comando}" do
          assert Permisos.permitido?(unquote(tipo), unquote(comando))
          assert Permisos.verificar(unquote(tipo), unquote(comando)) == :ok
        end
      end
    end
  end

  describe "comandos de coordinador o superior" do
    for comando <- @coordinador_o_superior do
      for tipo <- [:ciudadano, :voluntario] do
        test "#{tipo} no puede #{comando}" do
          refute Permisos.permitido?(unquote(tipo), unquote(comando))

          assert Permisos.verificar(unquote(tipo), unquote(comando)) ==
                   {:error, :permiso_denegado}
        end
      end

      for tipo <- [:coordinador, :administrador] do
        test "#{tipo} puede #{comando}" do
          assert Permisos.permitido?(unquote(tipo), unquote(comando))
          assert Permisos.verificar(unquote(tipo), unquote(comando)) == :ok
        end
      end
    end
  end

  describe "entradas inválidas" do
    test "un tipo desconocido no tiene permiso sobre un comando existente" do
      refute Permisos.permitido?(:visitante, :help)
      assert Permisos.verificar(:visitante, :help) == {:error, :permiso_denegado}
    end

    test "un comando como texto se considera desconocido" do
      refute Permisos.permitido?(:administrador, "help")
      assert Permisos.verificar(:administrador, "help") == {:error, :comando_desconocido}
    end

    test "un comando inexistente es desconocido para todos los tipos" do
      for tipo <- @tipos do
        refute Permisos.permitido?(tipo, :no_existe)
        assert Permisos.verificar(tipo, :no_existe) == {:error, :comando_desconocido}
      end
    end

    test "un tipo desconocido con comando inexistente da :comando_desconocido" do
      assert Permisos.verificar(:visitante, :no_existe) == {:error, :comando_desconocido}
    end
  end
end
