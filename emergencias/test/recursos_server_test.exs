defmodule Emergencias.Procesos.RecursosServerTest do
  # No es async: cada prueba cambia `:data_dir` (configuración global).
  use ExUnit.Case, async: false

  alias Emergencias.CSV
  alias Emergencias.Dominio.Movimiento
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Fabrica
  alias Emergencias.Persistencia
  alias Emergencias.Procesos.RecursosServer

  setup do
    anterior = Application.get_env(:emergencias, :data_dir)
    base = System.tmp_dir() || "."
    dir = Path.join(base, "emergencias_recursos_#{System.unique_integer([:positive])}")
    File.mkdir_p(dir)
    Application.put_env(:emergencias, :data_dir, dir)

    on_exit(fn ->
      if anterior do
        Application.put_env(:emergencias, :data_dir, anterior)
      else
        Application.delete_env(:emergencias, :data_dir)
      end

      File.rm_rf(dir)
    end)

    srv = :"recursos_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({RecursosServer, name: srv})

    %{srv: srv, dir: dir}
  end

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp crear(srv, id, categoria, cantidad, opciones \\ []) do
    ubicacion = Keyword.get(opciones, :ubicacion, "bodega")
    zona = Keyword.get(opciones, :zona, "centro")
    unidad = Keyword.get(opciones, :unidad, "unidad")
    RecursosServer.registrar(id, "recurso", categoria, cantidad, unidad, ubicacion, zona, srv)
  end

  defp reservar(srv, categoria, zona, cantidad) do
    RecursosServer.reservar(categoria, zona, cantidad, "N001", "laura", srv)
  end

  defp transferir(srv, id, centro, cantidad) do
    RecursosServer.transferir(id, centro, cantidad, "laura", srv)
  end

  defp stock(srv, id) do
    {:ok, recurso} = RecursosServer.obtener(id, srv)
    recurso.cantidad_disponible
  end

  defp movimientos_en_disco(dir) do
    {:ok, movimientos} = CSV.leer(Path.join(dir, "movimientos.csv"), &Movimiento.de_linea/1)
    movimientos
  end

  # ---------------------------------------------------------------------------
  # registrar
  # ---------------------------------------------------------------------------

  describe "registrar/8" do
    test "registra un recurso válido y lo guarda en recursos.csv", %{srv: srv} do
      assert {:ok, %Recurso{id: "R1", cantidad_disponible: 50}} = crear(srv, "R1", :agua, 50)
      assert {:ok, [%Recurso{id: "R1"}]} = Persistencia.cargar_recursos()
      assert {:ok, %Recurso{id: "R1"}} = RecursosServer.obtener("R1", srv)
    end

    test "rechaza un id duplicado y no cambia el recurso", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert crear(srv, "R1", :agua, 99) == {:error, :id_duplicado}
      assert stock(srv, "R1") == 50
    end

    test "rechaza un texto vacío", %{srv: srv} do
      assert crear(srv, "  ", :agua, 5) == {:error, :texto_vacio}
    end

    test "rechaza una categoría inválida", %{srv: srv} do
      assert crear(srv, "R1", :comida, 5) == {:error, :categoria_invalida}
    end

    test "rechaza una cantidad inválida", %{srv: srv} do
      assert crear(srv, "R1", :agua, -1) == {:error, :cantidad_invalida}
      assert Persistencia.cargar_recursos() == {:ok, []}
    end
  end

  # ---------------------------------------------------------------------------
  # entrada y salida
  # ---------------------------------------------------------------------------

  describe "entrada/4" do
    test "suma stock, guarda el movimiento y reescribe los archivos", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert {:ok, resultado} = RecursosServer.entrada("R1", 10, "laura", srv)
      assert resultado.recurso.cantidad_disponible == 60
      assert resultado.movimiento.id == "MV001"
      assert resultado.movimiento.tipo == :entrada
      assert resultado.movimiento.cantidad == 10
      assert resultado.movimiento.usuario == "laura"

      assert [%Movimiento{id: "MV001", tipo: :entrada}] = movimientos_en_disco(dir)
      assert {:ok, [%Recurso{cantidad_disponible: 60}]} = Persistencia.cargar_recursos()
    end

    test "rechaza una cantidad inválida", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.entrada("R1", 0, "laura", srv) == {:error, :cantidad_invalida}
      assert RecursosServer.entrada("R1", -5, "laura", srv) == {:error, :cantidad_invalida}
      assert stock(srv, "R1") == 50
    end

    test "rechaza un recurso inexistente", %{srv: srv} do
      assert RecursosServer.entrada("R9", 5, "laura", srv) == {:error, :recurso_no_encontrado}
    end

    test "rechaza un usuario vacío y no cambia el stock", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.entrada("R1", 5, " ", srv) == {:error, :texto_vacio}
      assert stock(srv, "R1") == 50
    end
  end

  describe "salida/4" do
    test "resta stock y guarda el movimiento", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert {:ok, resultado} = RecursosServer.salida("R1", 20, "laura", srv)
      assert resultado.recurso.cantidad_disponible == 30
      assert resultado.movimiento.tipo == :salida

      assert [%Movimiento{tipo: :salida, cantidad: 20}] = movimientos_en_disco(dir)
    end

    test "rechaza una salida mayor al stock", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.salida("R1", 51, "laura", srv) == {:error, :sin_stock}
      assert stock(srv, "R1") == 50
    end

    test "rechaza una cantidad inválida", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.salida("R1", 0, "laura", srv) == {:error, :cantidad_invalida}
    end

    test "rechaza un recurso inexistente", %{srv: srv} do
      assert RecursosServer.salida("R9", 5, "laura", srv) == {:error, :recurso_no_encontrado}
    end
  end

  # ---------------------------------------------------------------------------
  # reservar
  # ---------------------------------------------------------------------------

  describe "reservar/6" do
    test "reserva de un solo recurso", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert {:ok, %{movimientos: [movimiento]}} = reservar(srv, :agua, "centro", 30)
      assert movimiento.id == "MV001"
      assert movimiento.tipo == :asignacion
      assert movimiento.cantidad == 30
      assert movimiento.referencia == "N001"

      assert stock(srv, "R1") == 20
      assert [%Movimiento{id: "MV001"}] = movimientos_en_disco(dir)
      assert {:ok, [%Recurso{cantidad_disponible: 20}]} = Persistencia.cargar_recursos()
    end

    test "toma de varios recursos cuando uno solo no alcanza", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 20)
      {:ok, _} = crear(srv, "R2", :agua, 20)

      assert {:ok, %{movimientos: movimientos}} = reservar(srv, :agua, "centro", 30)
      assert Enum.map(movimientos, &{&1.recurso_id, &1.cantidad}) == [{"R1", 20}, {"R2", 10}]
      assert Enum.map(movimientos, & &1.id) == ["MV001", "MV002"]
      assert stock(srv, "R1") == 0
      assert stock(srv, "R2") == 10
    end

    test "sin stock suficiente no cambia nada", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert reservar(srv, :agua, "centro", 80) == {:error, :sin_stock}
      assert stock(srv, "R1") == 50
      refute File.exists?(Path.join(dir, "movimientos.csv"))
    end

    test "solo usa recursos de esa categoría y zona", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 10)
      {:ok, _} = crear(srv, "R2", :agua, 100, zona: "norte")
      {:ok, _} = crear(srv, "R3", :alimentos, 100)

      assert reservar(srv, :agua, "centro", 50) == {:error, :sin_stock}
      assert {:ok, %{movimientos: [_]}} = reservar(srv, :agua, "centro", 10)
      assert stock(srv, "R2") == 100
      assert stock(srv, "R3") == 100
    end

    test "rechaza una cantidad inválida", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert reservar(srv, :agua, "centro", 0) == {:error, :cantidad_invalida}
    end

    test "rechaza un usuario vacío y no cambia el stock", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.reservar(:agua, "centro", 5, "N001", " ", srv) ==
               {:error, :texto_vacio}

      assert stock(srv, "R1") == 50
    end

    test "peticiones simultáneas nunca superan el stock", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      resultados =
        1..20
        |> Task.async_stream(fn _ -> reservar(srv, :agua, "centro", 5) end, max_concurrency: 20)
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
      assert Enum.count(resultados, &(&1 == {:error, :sin_stock})) == 10
      assert stock(srv, "R1") == 0
      assert length(movimientos_en_disco(dir)) == 10
    end
  end

  # ---------------------------------------------------------------------------
  # devolver
  # ---------------------------------------------------------------------------

  describe "devolver/2" do
    test "revierte una reserva y registra la entrada", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, %{movimientos: movimientos}} = reservar(srv, :agua, "centro", 30)
      assert stock(srv, "R1") == 20

      assert {:ok, %{movimientos: [devolucion]}} = RecursosServer.devolver(movimientos, srv)
      assert devolucion.id == "MV002"
      assert devolucion.tipo == :entrada
      assert devolucion.cantidad == 30
      assert devolucion.referencia == "devolucion"

      assert stock(srv, "R1") == 50
      assert length(movimientos_en_disco(dir)) == 2
    end

    test "revierte una reserva repartida entre varios recursos", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 20)
      {:ok, _} = crear(srv, "R2", :agua, 20)
      {:ok, %{movimientos: movimientos}} = reservar(srv, :agua, "centro", 30)

      assert {:ok, %{movimientos: devoluciones}} = RecursosServer.devolver(movimientos, srv)
      assert length(devoluciones) == 2
      assert stock(srv, "R1") == 20
      assert stock(srv, "R2") == 20
    end

    test "una lista vacía no hace nada", %{srv: srv} do
      assert RecursosServer.devolver([], srv) == {:ok, %{movimientos: []}}
    end

    test "rechaza un movimiento que el servidor no guardó", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      falso = Fabrica.movimiento(id: "MV999", tipo: :asignacion)

      assert RecursosServer.devolver([falso], srv) == {:error, :movimiento_desconocido}
      assert stock(srv, "R1") == 50
    end

    test "rechaza un movimiento que no es una asignación", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, %{movimiento: entrada}} = RecursosServer.entrada("R1", 10, "laura", srv)

      assert RecursosServer.devolver([entrada], srv) == {:error, :movimiento_desconocido}
      assert stock(srv, "R1") == 60
    end

    test "rechaza ids repetidos y no cambia nada", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, %{movimientos: [movimiento]}} = reservar(srv, :agua, "centro", 30)

      assert RecursosServer.devolver([movimiento, movimiento], srv) ==
               {:error, :movimientos_invalidos}

      assert stock(srv, "R1") == 20
    end

    test "rechaza algo que no es una lista de movimientos", %{srv: srv} do
      assert RecursosServer.devolver([:otro], srv) == {:error, :movimientos_invalidos}
      assert RecursosServer.devolver(:otro, srv) == {:error, :movimientos_invalidos}
    end
  end

  # ---------------------------------------------------------------------------
  # transferir
  # ---------------------------------------------------------------------------

  describe "transferir/5" do
    test "crea el destino cuando no existe", %{srv: srv, dir: dir} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert {:ok, resultado} = transferir(srv, "R1", "refugio", 20)
      assert resultado.origen.cantidad_disponible == 30
      assert resultado.destino.id == "R1-refugio"
      assert resultado.destino.cantidad_disponible == 20
      assert Enum.map(resultado.movimientos, & &1.id) == ["MV001", "MV002"]

      assert Enum.map(resultado.movimientos, & &1.tipo) ==
               [:transferencia_salida, :transferencia_entrada]

      assert stock(srv, "R1") == 30
      assert stock(srv, "R1-refugio") == 20
      assert {:ok, [_, _]} = Persistencia.cargar_recursos()
      assert length(movimientos_en_disco(dir)) == 2
    end

    test "usa el destino existente (misma categoría, unidad y zona)", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, _} = crear(srv, "R2", :agua, 5, ubicacion: "refugio")

      assert {:ok, resultado} = transferir(srv, "R1", "refugio", 20)
      assert resultado.destino.id == "R2"
      assert stock(srv, "R1") == 30
      assert stock(srv, "R2") == 25
    end

    test "ignora recursos de otra zona o unidad como destino", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, _} = crear(srv, "R2", :agua, 5, ubicacion: "refugio", zona: "norte")

      assert {:ok, resultado} = transferir(srv, "R1", "refugio", 20)
      assert resultado.destino.id == "R1-refugio"
      assert stock(srv, "R2") == 5
    end

    test "rechaza transferir al mismo centro", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert transferir(srv, "R1", "bodega", 5) == {:error, :mismo_centro}
      assert stock(srv, "R1") == 50
    end

    test "rechaza una cantidad mayor al stock", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert transferir(srv, "R1", "refugio", 51) == {:error, :sin_stock}
      assert stock(srv, "R1") == 50
      assert RecursosServer.obtener("R1-refugio", srv) == {:error, :recurso_no_encontrado}
    end

    test "rechaza una cantidad inválida", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert transferir(srv, "R1", "refugio", 0) == {:error, :cantidad_invalida}
    end

    test "rechaza un origen inexistente", %{srv: srv} do
      assert transferir(srv, "R9", "refugio", 5) == {:error, :recurso_no_encontrado}
    end

    test "rechaza un centro de destino vacío", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert transferir(srv, "R1", " ", 5) == {:error, :texto_vacio}
    end

    test "no pisa un recurso existente con el id del destino nuevo", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, _} = crear(srv, "R1-refugio", :agua, 7, ubicacion: "otro", unidad: "galones")

      assert transferir(srv, "R1", "refugio", 5) == {:error, :id_duplicado}
      assert stock(srv, "R1") == 50
      assert stock(srv, "R1-refugio") == 7
    end
  end

  # ---------------------------------------------------------------------------
  # consultas
  # ---------------------------------------------------------------------------

  describe "disponibilidad/3" do
    test "suma la categoría y zona pedidas", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 30)
      {:ok, _} = crear(srv, "R2", :agua, 20)
      {:ok, _} = crear(srv, "R3", :agua, 100, zona: "norte")

      assert RecursosServer.disponibilidad(:agua, "centro", srv) == {:ok, 50}
      assert RecursosServer.disponibilidad(:agua, "sur", srv) == {:ok, 0}
    end
  end

  describe "listar/2" do
    test "sin filtros devuelve todos ordenados por id", %{srv: srv} do
      {:ok, _} = crear(srv, "R2", :agua, 1)
      {:ok, _} = crear(srv, "R1", :alimentos, 1)

      assert {:ok, lista} = RecursosServer.listar([], srv)
      assert Enum.map(lista, & &1.id) == ["R1", "R2"]
    end

    test "filtra por categoría, zona y ubicación", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 1)
      {:ok, _} = crear(srv, "R2", :alimentos, 1)
      {:ok, _} = crear(srv, "R3", :agua, 1, zona: "norte", ubicacion: "refugio")

      assert {:ok, [%Recurso{id: "R1"}, %Recurso{id: "R3"}]} =
               RecursosServer.listar([categoria: :agua], srv)

      assert {:ok, [%Recurso{id: "R3"}]} = RecursosServer.listar(%{zona: "norte"}, srv)

      assert {:ok, [%Recurso{id: "R3"}]} =
               RecursosServer.listar([categoria: :agua, ubicacion: "refugio"], srv)
    end

    test "rechaza filtros inválidos", %{srv: srv} do
      assert RecursosServer.listar([color: "rojo"], srv) == {:error, :filtro_invalido}
      assert RecursosServer.listar(:otro, srv) == {:error, :filtro_invalido}
    end
  end

  describe "historial/2" do
    test "devuelve los movimientos del recurso del más antiguo al más reciente", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, _} = crear(srv, "R2", :agua, 50)
      {:ok, _} = RecursosServer.entrada("R1", 10, "laura", srv)
      {:ok, _} = RecursosServer.entrada("R2", 10, "laura", srv)
      {:ok, _} = RecursosServer.salida("R1", 5, "laura", srv)

      assert {:ok, historial} = RecursosServer.historial("R1", srv)
      assert Enum.map(historial, &{&1.id, &1.tipo}) == [{"MV001", :entrada}, {"MV003", :salida}]
    end

    test "un recurso sin movimientos tiene historial vacío", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert RecursosServer.historial("R1", srv) == {:ok, []}
    end

    test "rechaza un recurso inexistente", %{srv: srv} do
      assert RecursosServer.historial("R9", srv) == {:error, :recurso_no_encontrado}
    end
  end

  describe "obtener/2" do
    test "devuelve el recurso", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)

      assert {:ok, recurso} = RecursosServer.obtener("R1", srv)
      assert recurso.id == "R1"
      assert recurso.cantidad_disponible == 50
    end

    test "rechaza un recurso inexistente", %{srv: srv} do
      assert RecursosServer.obtener("R9", srv) == {:error, :recurso_no_encontrado}
    end
  end

  # ---------------------------------------------------------------------------
  # arranque y persistencia
  # ---------------------------------------------------------------------------

  describe "arranque" do
    test "recupera recursos y movimientos al reiniciar", %{srv: srv} do
      {:ok, _} = crear(srv, "R1", :agua, 50)
      {:ok, _} = RecursosServer.entrada("R1", 10, "laura", srv)
      {:ok, _} = RecursosServer.salida("R1", 5, "laura", srv)

      :ok = stop_supervised(RecursosServer)
      {:ok, _pid} = start_supervised({RecursosServer, name: srv})

      assert stock(srv, "R1") == 55
      assert {:ok, [_, _]} = RecursosServer.historial("R1", srv)
      assert {:ok, %{movimiento: movimiento}} = RecursosServer.entrada("R1", 1, "laura", srv)
      assert movimiento.id == "MV003"
    end

    test "falla si recursos.csv está corrupto", %{dir: dir} do
      File.write(Path.join(dir, "recursos.csv"), "cabecera\nbasura\n")
      Process.flag(:trap_exit, true)

      assert {:error, {:linea_invalida, 2}} = RecursosServer.start_link(name: :recursos_corrupto)
    end

    test "sin servidor en ejecución devuelve :servidor_no_disponible" do
      assert RecursosServer.obtener("R1", :servidor_inexistente) ==
               {:error, :servidor_no_disponible}
    end
  end
end
