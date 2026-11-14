defmodule Emergencias.Servicios.AsignacionServicioTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Movimiento, Necesidad, Recurso}
  alias Emergencias.Servicios.AsignacionServicio

  # -- Ayudas -----------------------------------------------------------------

  defp recurso(id, categoria, cantidad, opciones \\ []) do
    {:ok, recurso} =
      Recurso.crear(
        id,
        Keyword.get(opciones, :nombre, "Recurso #{id}"),
        categoria,
        cantidad,
        Keyword.get(opciones, :unidad, "litros"),
        Keyword.get(opciones, :ubicacion, "Bodega Central"),
        Keyword.get(opciones, :zona, "centro")
      )

    recurso
  end

  defp necesidad(id, tipo, requerida) do
    {:ok, necesidad} =
      Necesidad.crear(id, tipo, nil, "Necesidad de prueba", requerida, "centro", :alta, "coord1")

    necesidad
  end

  defp necesidad_atendida do
    {:ok, asignada} = Necesidad.cambiar_estado(necesidad("N009", :agua, 50), :asignada)
    {:ok, en_atencion} = Necesidad.cambiar_estado(asignada, :en_atencion)
    {:ok, atendida} = Necesidad.cambiar_estado(en_atencion, :atendida)
    atendida
  end

  defp cantidades(recursos), do: Enum.map(recursos, & &1.cantidad_disponible)

  # -- reservar/5 -------------------------------------------------------------

  describe "reservar/5" do
    test "alcanza con un solo recurso" do
      recursos = [recurso("R001", :agua, 100)]

      assert {:ok, %{recursos: [r1], movimientos: [mov]}} =
               AsignacionServicio.reservar(recursos, :agua, 30, "N001", "ana")

      assert r1.id == "R001"
      assert r1.cantidad_disponible == 70
      assert %Movimiento{} = mov
      assert mov.id == nil
      assert mov.recurso_id == "R001"
      assert mov.tipo == :asignacion
      assert mov.cantidad == 30
      assert mov.usuario == "ana"
      assert mov.referencia == "N001"
    end

    test "alcanza combinando dos recursos (recursión)" do
      recursos = [recurso("R001", :agua, 20), recurso("R002", :agua, 50)]

      assert {:ok, %{recursos: actualizados, movimientos: [m1, m2]}} =
               AsignacionServicio.reservar(recursos, :agua, 60, "N001", "ana")

      assert cantidades(actualizados) == [0, 10]
      assert {m1.recurso_id, m1.cantidad} == {"R001", 20}
      assert {m2.recurso_id, m2.cantidad} == {"R002", 40}
      assert Enum.all?([m1, m2], &(&1.tipo == :asignacion and &1.referencia == "N001"))
    end

    test "combina tres recursos y deja intacto el que no hace falta" do
      recursos = [
        recurso("R001", :agua, 10),
        recurso("R002", :agua, 10),
        recurso("R003", :agua, 10),
        recurso("R004", :agua, 99)
      ]

      assert {:ok, %{recursos: actualizados, movimientos: movimientos}} =
               AsignacionServicio.reservar(recursos, :agua, 25, "N001", "ana")

      assert cantidades(actualizados) == [0, 0, 5, 99]
      assert Enum.map(movimientos, & &1.cantidad) == [10, 10, 5]
    end

    test "gasta exactamente todo el stock disponible" do
      recursos = [recurso("R001", :agua, 20), recurso("R002", :agua, 30)]

      assert {:ok, %{recursos: actualizados, movimientos: movimientos}} =
               AsignacionServicio.reservar(recursos, :agua, 50, "N001", "ana")

      assert cantidades(actualizados) == [0, 0]
      assert length(movimientos) == 2
    end

    test "ignora recursos de otra categoría y con cantidad 0, y los deja sin cambios" do
      alimentos = recurso("R001", :alimentos, 100)
      agotado = recurso("R002", :agua, 0)
      agua = recurso("R003", :agua, 10)

      assert {:ok, %{recursos: [r1, r2, r3], movimientos: [mov]}} =
               AsignacionServicio.reservar([alimentos, agotado, agua], :agua, 5, "N001", "ana")

      assert r1 == alimentos
      assert r2 == agotado
      assert r3.cantidad_disponible == 5
      assert mov.recurso_id == "R003"
      assert mov.cantidad == 5
    end

    test "conserva el orden original de los recursos" do
      recursos = [recurso("R001", :agua, 5), recurso("R002", :agua, 5), recurso("R003", :agua, 5)]

      assert {:ok, %{recursos: actualizados}} =
               AsignacionServicio.reservar(recursos, :agua, 7, "N001", "ana")

      assert Enum.map(actualizados, & &1.id) == ["R001", "R002", "R003"]
    end

    test "no alcanza: devuelve :sin_stock y no cambia nada" do
      recursos = [recurso("R001", :agua, 20), recurso("R002", :agua, 30)]

      assert {:error, :sin_stock} =
               AsignacionServicio.reservar(recursos, :agua, 51, "N001", "ana")

      assert cantidades(recursos) == [20, 30]
    end

    test "no cuenta el stock de otras categorías" do
      recursos = [recurso("R001", :alimentos, 500), recurso("R002", :agua, 10)]

      assert {:error, :sin_stock} =
               AsignacionServicio.reservar(recursos, :agua, 11, "N001", "ana")
    end

    test "sin candidatos devuelve :sin_stock" do
      assert {:error, :sin_stock} = AsignacionServicio.reservar([], :agua, 1, "N001", "ana")
    end

    test "cantidad que no es un entero mayor que 0 devuelve :cantidad_invalida" do
      recursos = [recurso("R001", :agua, 100)]

      for cantidad <- [0, -5, 2.5, "5", nil] do
        assert {:error, :cantidad_invalida} =
                 AsignacionServicio.reservar(recursos, :agua, cantidad, "N001", "ana")
      end
    end

    test "usuario vacío devuelve el error de Movimiento y no cambia nada" do
      recursos = [recurso("R001", :agua, 100)]

      assert {:error, :texto_vacio} =
               AsignacionServicio.reservar(recursos, :agua, 10, "N001", "  ")

      assert cantidades(recursos) == [100]
    end
  end

  # -- asignar/4 --------------------------------------------------------------

  describe "asignar/4" do
    test "cubre la necesidad completa: pasa a :asignada" do
      necesidad = necesidad("N001", :agua, 50)
      recursos = [recurso("R001", :agua, 20), recurso("R002", :agua, 50)]

      assert {:ok, resultado} = AsignacionServicio.asignar(necesidad, recursos, 50, "ana")

      assert resultado.necesidad.cantidad_asignada == 50
      assert resultado.necesidad.estado == :asignada
      assert cantidades(resultado.recursos) == [0, 20]
      assert Enum.map(resultado.movimientos, & &1.cantidad) == [20, 30]
      assert Enum.all?(resultado.movimientos, &(&1.referencia == "N001"))
    end

    test "cobertura parcial: la necesidad sigue :pendiente" do
      necesidad = necesidad("N001", :agua, 50)
      recursos = [recurso("R001", :agua, 100)]

      assert {:ok, resultado} = AsignacionServicio.asignar(necesidad, recursos, 20, "ana")

      assert resultado.necesidad.cantidad_asignada == 20
      assert resultado.necesidad.estado == :pendiente
      assert cantidades(resultado.recursos) == [80]
    end

    test "necesidad atendida devuelve :ya_cerrada" do
      recursos = [recurso("R001", :agua, 100)]

      assert {:error, :ya_cerrada} =
               AsignacionServicio.asignar(necesidad_atendida(), recursos, 10, "ana")
    end

    test "cantidad mayor que la requerida devuelve :excede_requerido" do
      recursos = [recurso("R001", :agua, 100)]

      assert {:error, :excede_requerido} =
               AsignacionServicio.asignar(necesidad("N001", :agua, 50), recursos, 60, "ana")
    end

    test "sin stock suficiente devuelve :sin_stock" do
      recursos = [recurso("R001", :agua, 10)]

      assert {:error, :sin_stock} =
               AsignacionServicio.asignar(necesidad("N001", :agua, 50), recursos, 20, "ana")
    end

    test "cantidad inválida devuelve :cantidad_invalida" do
      recursos = [recurso("R001", :agua, 10)]

      assert {:error, :cantidad_invalida} =
               AsignacionServicio.asignar(necesidad("N001", :agua, 50), recursos, 0, "ana")
    end

    test "usa solo recursos de la categoría de la necesidad" do
      recursos = [recurso("R001", :alimentos, 100), recurso("R002", :agua, 100)]

      assert {:ok, resultado} =
               AsignacionServicio.asignar(necesidad("N001", :agua, 50), recursos, 50, "ana")

      assert cantidades(resultado.recursos) == [100, 50]
    end
  end

  # -- transferir/5 -----------------------------------------------------------

  describe "transferir/5" do
    test "hacia un destino nuevo crea el recurso con los datos del origen" do
      origen = recurso("R001", :agua, 100, nombre: "Agua embotellada", unidad: "botellas")

      assert {:ok, %{origen: origen_nuevo, destino: destino, movimientos: [salida, entrada]}} =
               AsignacionServicio.transferir(origen, nil, 30, "Bodega Norte", "ana")

      assert origen_nuevo.cantidad_disponible == 70

      assert destino.id == "R001-Bodega Norte"
      assert destino.nombre == "Agua embotellada"
      assert destino.categoria == :agua
      assert destino.unidad == "botellas"
      assert destino.zona == "centro"
      assert destino.ubicacion == "Bodega Norte"
      assert destino.cantidad_disponible == 30

      assert salida.tipo == :transferencia_salida
      assert salida.recurso_id == "R001"
      assert salida.cantidad == 30
      assert salida.usuario == "ana"
      assert salida.referencia == "Bodega Norte"

      assert entrada.tipo == :transferencia_entrada
      assert entrada.recurso_id == "R001-Bodega Norte"
      assert entrada.cantidad == 30
      assert entrada.referencia == "Bodega Central"
    end

    test "hacia un destino existente le suma la cantidad" do
      origen = recurso("R001", :agua, 100)
      destino = recurso("R002", :agua, 10, ubicacion: "Bodega Norte")

      assert {:ok, resultado} =
               AsignacionServicio.transferir(origen, destino, 40, "Bodega Norte", "ana")

      assert resultado.origen.cantidad_disponible == 60
      assert resultado.destino.id == "R002"
      assert resultado.destino.cantidad_disponible == 50
      assert [%{recurso_id: "R001"}, %{recurso_id: "R002"}] = resultado.movimientos
    end

    test "puede transferir todo el stock del origen" do
      origen = recurso("R001", :agua, 25)

      assert {:ok, resultado} =
               AsignacionServicio.transferir(origen, nil, 25, "Bodega Norte", "ana")

      assert resultado.origen.cantidad_disponible == 0
      assert resultado.destino.cantidad_disponible == 25
    end

    test "cantidad mayor que la disponible devuelve :sin_stock" do
      origen = recurso("R001", :agua, 10)

      assert {:error, :sin_stock} =
               AsignacionServicio.transferir(origen, nil, 11, "Bodega Norte", "ana")
    end

    test "cantidad que no es un entero mayor que 0 devuelve :cantidad_invalida" do
      origen = recurso("R001", :agua, 10)

      for cantidad <- [0, -1, 1.5, "3", nil] do
        assert {:error, :cantidad_invalida} =
                 AsignacionServicio.transferir(origen, nil, cantidad, "Bodega Norte", "ana")
      end
    end

    test "mismo centro sin destino devuelve :mismo_centro" do
      origen = recurso("R001", :agua, 10)

      assert {:error, :mismo_centro} =
               AsignacionServicio.transferir(origen, nil, 5, "Bodega Central", "ana")
    end

    test "destino existente en el mismo centro devuelve :mismo_centro" do
      origen = recurso("R001", :agua, 10)
      destino = recurso("R002", :agua, 10)

      assert {:error, :mismo_centro} =
               AsignacionServicio.transferir(origen, destino, 5, "Bodega Central", "ana")
    end

    test "destino de otra zona devuelve :destino_invalido (entre zonas no se soporta)" do
      origen = recurso("R001", :agua, 10)
      destino = recurso("R002", :agua, 10, ubicacion: "Bodega Norte", zona: "norte")

      assert {:error, :destino_invalido} =
               AsignacionServicio.transferir(origen, destino, 5, "Bodega Norte", "ana")
    end

    test "destino de otra categoría o unidad devuelve :destino_invalido" do
      origen = recurso("R001", :agua, 10)
      otra_categoria = recurso("R002", :alimentos, 10, ubicacion: "Bodega Norte")
      otra_unidad = recurso("R003", :agua, 10, ubicacion: "Bodega Norte", unidad: "galones")

      assert {:error, :destino_invalido} =
               AsignacionServicio.transferir(origen, otra_categoria, 5, "Bodega Norte", "ana")

      assert {:error, :destino_invalido} =
               AsignacionServicio.transferir(origen, otra_unidad, 5, "Bodega Norte", "ana")
    end

    test "destino cuya ubicación no es el centro indicado devuelve :destino_invalido" do
      origen = recurso("R001", :agua, 10)
      destino = recurso("R002", :agua, 10, ubicacion: "Bodega Norte")

      assert {:error, :destino_invalido} =
               AsignacionServicio.transferir(origen, destino, 5, "Bodega Sur", "ana")
    end

    test "centro de destino vacío devuelve :texto_vacio" do
      origen = recurso("R001", :agua, 10)

      assert {:error, :texto_vacio} = AsignacionServicio.transferir(origen, nil, 5, "  ", "ana")
    end

    test "usuario vacío devuelve :texto_vacio" do
      origen = recurso("R001", :agua, 10)

      assert {:error, :texto_vacio} =
               AsignacionServicio.transferir(origen, nil, 5, "Bodega Norte", "")
    end
  end
end
