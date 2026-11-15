defmodule Emergencias.ConcurrenciaTest do
  @moduledoc """
  Conflictos de concurrencia del enunciado, probados contra la aplicación
  completa y la fachada `Emergencias`.

  Cada prueba arranca la aplicación con la carpeta de datos vacía. Los
  servidores tienen nombre global, por eso `async: false`.
  """

  use ExUnit.Case, async: false

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Procesos.MascotasServer
  alias Emergencias.Procesos.NecesidadesServer
  alias Emergencias.Procesos.PersonasServer
  alias Emergencias.Procesos.RecursosServer
  alias Emergencias.TestHelperApp, as: App

  setup do
    on_exit(&App.detener_y_limpiar/0)
    :ok = App.reiniciar()
    {:ok, usuario} = App.preparar_escenario()
    %{usuario: usuario}
  end

  test "1. conflicto del enunciado: 50 L, dos necesidades (30 y 25) a la vez", %{usuario: usuario} do
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 50)
    {:ok, grande} = App.registrar_necesidad_agua(usuario, 30)
    {:ok, pequena} = App.registrar_necesidad_agua(usuario, 25)

    resultados =
      App.en_paralelo([grande, pequena], fn necesidad ->
        Emergencias.assign_resource(usuario, necesidad.id, :agua, necesidad.cantidad_requerida)
      end)

    assert App.contar(resultados) == %{:ok => 1, {:error, :sin_stock} => 1}

    {:ok, recurso} = RecursosServer.obtener("R001")
    assert recurso.cantidad_disponible in [20, 25]

    # El inventario descontado coincide con lo que quedó asignado a las necesidades.
    {:ok, necesidades} = NecesidadesServer.listar()
    asignado = necesidades |> Enum.map(& &1.cantidad_asignada) |> Enum.sum()
    assert asignado + recurso.cantidad_disponible == 50
  end

  test "2. cien solicitudes de 1 L sobre un recurso de 50 L", %{usuario: usuario} do
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 50)
    # Necesita 100 L para que ninguna solicitud falle por exceder lo requerido:
    # los únicos errores posibles son de stock.
    {:ok, necesidad} = App.registrar_necesidad_agua(usuario, 100)

    resultados =
      App.en_paralelo(1..100, fn _i ->
        Emergencias.assign_resource(usuario, necesidad.id, :agua, 1)
      end)

    assert App.contar(resultados) == %{:ok => 50, {:error, :sin_stock} => 50}

    {:ok, recurso} = RecursosServer.obtener("R001")
    assert recurso.cantidad_disponible == 0

    {:ok, necesidad} = NecesidadesServer.obtener(necesidad.id)
    assert necesidad.cantidad_asignada == 50

    {:ok, historial} = RecursosServer.historial("R001")
    reservado = historial |> Enum.filter(&(&1.tipo == :asignacion)) |> Enum.map(& &1.cantidad)
    assert Enum.sum(reservado) == 50
  end

  test "3. cerrar dos veces: 20 tareas confirman el mismo par de mascotas", %{usuario: usuario} do
    {:ok, perdida} =
      Emergencias.report_pet(
        usuario,
        :perdida,
        "perro",
        "Luna",
        "negra",
        :mediano,
        "centro",
        "3001234567"
      )

    {:ok, encontrada} =
      Emergencias.report_pet(
        usuario,
        :encontrada,
        "perro",
        "Desconocido",
        "negra",
        :mediano,
        "centro",
        "3009876543"
      )

    {:ok, _par} = MascotasServer.registrar_posible_coincidencia(perdida.id, encontrada.id)

    resultados =
      App.en_paralelo(1..20, fn _i ->
        Emergencias.confirm_pet_match(usuario, perdida.id, encontrada.id)
      end)

    assert App.contar(resultados) == %{:ok => 1, {:error, :ya_resuelta} => 19}

    {:ok, resueltas} = Emergencias.list_pets(usuario, estado: :resuelta)
    assert resueltas |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([perdida.id, encontrada.id])
  end

  test "4. capacidad del albergue: 50 ingresos simultáneos a un albergue de 10", %{
    usuario: usuario
  } do
    {:ok, _albergue} =
      Emergencias.register_shelter(usuario, "A01", "Albergue Norte", "centro", 10)

    {:ok, documentos} = App.reportar_personas(usuario, 50)

    resultados =
      App.en_paralelo(documentos, fn documento ->
        Emergencias.register_entry(usuario, "A01", documento)
      end)

    assert App.contar(resultados) == %{:ok => 10, {:error, :sin_cupo} => 40}

    {:ok, albergue} = Emergencias.check_shelter(usuario, "A01")
    assert albergue.ocupacion_actual == 10
    assert MapSet.size(albergue.personas) == 10
    assert Albergue.cupos_disponibles(albergue) == 0

    # El albergue y las personas coinciden: solo las 10 que ingresaron están :en_albergue.
    {:ok, alojadas} = PersonasServer.buscar(estado: :en_albergue)
    assert alojadas |> Enum.map(& &1.documento) |> MapSet.new() == albergue.personas
  end

  test "5. compensación: dos asignaciones de 30 a una necesidad de 30 (stock 100)", %{
    usuario: usuario
  } do
    {:ok, _recurso} = App.registrar_agua(usuario, "R001", 100)
    {:ok, necesidad} = App.registrar_necesidad_agua(usuario, 30)

    resultados =
      App.en_paralelo(1..2, fn _i ->
        Emergencias.assign_resource(usuario, necesidad.id, :agua, 30)
      end)

    # La segunda reserva sí encuentra stock, pero la necesidad ya está cubierta:
    # `registrar_asignacion` falla y la fachada devuelve la reserva.
    assert App.contar(resultados) == %{:ok => 1, {:error, :excede_requerido} => 1}

    {:ok, recurso} = RecursosServer.obtener("R001")
    assert recurso.cantidad_disponible == 70

    {:ok, necesidad} = NecesidadesServer.obtener(necesidad.id)
    assert necesidad.cantidad_asignada == 30
    assert necesidad.estado == :asignada

    # La devolución quedó registrada como entrada con referencia "devolucion".
    {:ok, historial} = RecursosServer.historial("R001")

    devoluciones =
      Enum.filter(historial, fn m -> m.tipo == :entrada and m.referencia == "devolucion" end)

    assert [%{cantidad: 30}] = devoluciones
  end
end
