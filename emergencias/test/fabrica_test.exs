defmodule Emergencias.FabricaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Fabrica

  defmodule Ejemplo do
    defstruct [:id, :nombre, cantidad: 0]
  end

  describe "construir/3" do
    test "usa los valores por defecto" do
      ejemplo = Fabrica.construir(Ejemplo, id: "E1", nombre: "agua")

      assert %Ejemplo{id: "E1", nombre: "agua", cantidad: 0} = ejemplo
    end

    test "los atributos sobrescriben los valores por defecto (keyword o mapa)" do
      base = [id: "E1", nombre: "agua"]

      assert %Ejemplo{nombre: "pan"} = Fabrica.construir(Ejemplo, base, nombre: "pan")
      assert %Ejemplo{cantidad: 9} = Fabrica.construir(Ejemplo, base, %{cantidad: 9})
    end

    test "un campo que no existe en la struct falla de inmediato" do
      assert_raise KeyError, fn ->
        Fabrica.construir(Ejemplo, [id: "E1"], campo_inexistente: 1)
      end
    end
  end

  # Una prueba por fábrica. Se activa sola cuando existe el módulo de la entidad
  # (es decir, cuando se fusiona el issue de esa entidad).
  for {funcion, modulo} <- [
        usuario: Emergencias.Dominio.Usuario,
        zona: Emergencias.Dominio.Zona,
        sector: Emergencias.Dominio.Sector,
        punto_atencion: Emergencias.Dominio.PuntoAtencion,
        necesidad: Emergencias.Dominio.Necesidad,
        recurso: Emergencias.Dominio.Recurso,
        persona: Emergencias.Dominio.Persona,
        mascota: Emergencias.Dominio.Mascota,
        albergue: Emergencias.Dominio.Albergue
      ] do
    if Code.ensure_loaded?(modulo) do
      test "#{funcion}/1 construye una struct #{inspect(modulo)} y acepta sobrescrituras" do
        assert %{__struct__: unquote(modulo)} = apply(Fabrica, unquote(funcion), [])

        campo = unquote(modulo).__struct__() |> Map.keys() |> Enum.find(&(&1 != :__struct__))

        assert %{^campo => :sobrescrito} =
                 apply(Fabrica, unquote(funcion), [[{campo, :sobrescrito}]])
      end
    end
  end
end
