defmodule Emergencias.CLI.ComandosTest do
  use ExUnit.Case, async: false

  setup_all do
    estaba_arriba? =
      Enum.any?(Application.started_applications(), fn {app, _, _} -> app == :emergencias end)

    {:ok, _} = Application.ensure_all_started(:emergencias)

    # Deja todo como lo encontró: si la app estaba detenida, la detiene al terminar.
    unless estaba_arriba?, do: on_exit(fn -> Application.stop(:emergencias) end)

    :ok
  end

  alias Emergencias.CLI.Comandos
  alias Emergencias.Dominio.Usuario

  defp nombre_unico, do: "cmd_#{System.unique_integer([:positive])}"

  describe "connect y disconnect (versión mínima del issue #29)" do
    test "connect devuelve el usuario conectado y disconnect lo desconecta" do
      nombre = nombre_unico()

      assert {:ok, %Usuario{username: ^nombre, tipo: :coordinador, conectado: true} = usuario} =
               Comandos.ejecutar(nil, :connect, [nombre, "1234", :coordinador, "centro"])

      assert :ok = Comandos.ejecutar(usuario, :disconnect, [])
    end

    test "connect con contraseña incorrecta" do
      nombre = nombre_unico()
      {:ok, usuario} = Comandos.ejecutar(nil, :connect, [nombre, "1234", :ciudadano, "centro"])
      :ok = Comandos.ejecutar(usuario, :disconnect, [])

      assert {:error, :credenciales_invalidas} =
               Comandos.ejecutar(nil, :connect, [nombre, "otra", :ciudadano, "centro"])
    end
  end

  # Prueba temporal: borrarla cuando los issues #30 a #32 reemplacen este módulo.
  test "un comando que aún no existe devuelve :no_implementado" do
    assert {:error, :no_implementado} = Comandos.ejecutar(nil, :zone_status, ["centro"])
  end
end
