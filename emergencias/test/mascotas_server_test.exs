defmodule Emergencias.Procesos.MascotasServerTest do
  # No es async: cada prueba se ubica en un directorio temporal para no tocar
  # el `mascotas.csv` real, y `File.cd/1` afecta a todo el proceso de la VM.
  use ExUnit.Case, async: false

  alias Emergencias.Dominio.Mascota
  alias Emergencias.Procesos.MascotasServer

  @datos_base %{
    especie: "perro",
    nombre: "Firulais",
    caracteristicas: "collar rojo",
    color: "marrón",
    tamano: :mediano,
    zona: "Centro",
    contacto: "3001234567"
  }

  setup do
    {:ok, cwd} = File.cwd()
    tmp = Path.join(System.tmp_dir(), "mascotas_test_#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(tmp)
    :ok = File.cd(tmp)

    on_exit(fn ->
      File.cd(cwd)
      File.rm_rf(tmp)
    end)

    {:ok, pid: iniciar(:servidor_principal)}
  end

  # ---------------------------------------------------------------------------
  # reportar/9
  # ---------------------------------------------------------------------------

  describe "reportar" do
    test "crea un reporte activo con id M001", %{pid: pid} do
      assert {:ok, %Mascota{} = mascota} =
               MascotasServer.reportar(
                 pid,
                 :perdida,
                 "perro",
                 "Firulais",
                 "collar rojo",
                 "marrón",
                 :mediano,
                 "Centro",
                 "3001234567"
               )

      assert mascota.id == "M001"
      assert mascota.tipo == :perdida
      assert mascota.estado == :activa
    end

    test "los ids son consecutivos", %{pid: pid} do
      assert reportar_ok(pid, :perdida).id == "M001"
      assert reportar_ok(pid, :encontrada).id == "M002"
      assert reportar_ok(pid, :perdida).id == "M003"
    end

    test "tipo inválido", %{pid: pid} do
      assert {:error, :tipo_invalido} = reportar(pid, :otro, %{})
    end

    test "tamaño inválido", %{pid: pid} do
      assert {:error, :tamano_invalido} = reportar(pid, :perdida, %{tamano: :gigantesco})
    end

    test "especie vacía", %{pid: pid} do
      assert {:error, :especie_vacia} = reportar(pid, :perdida, %{especie: ""})
    end

    test "color vacío", %{pid: pid} do
      assert {:error, :color_vacio} = reportar(pid, :perdida, %{color: ""})
    end

    test "contacto vacío", %{pid: pid} do
      assert {:error, :contacto_vacio} = reportar(pid, :perdida, %{contacto: ""})
    end

    test "un reporte inválido no consume id", %{pid: pid} do
      assert {:error, :especie_vacia} = reportar(pid, :perdida, %{especie: ""})
      assert reportar_ok(pid, :perdida).id == "M001"
    end
  end

  # ---------------------------------------------------------------------------
  # consultar/2
  # ---------------------------------------------------------------------------

  describe "consultar" do
    setup %{pid: pid} do
      perro = reportar_ok(pid, :perdida, %{especie: "perro", zona: "Centro"})
      gato = reportar_ok(pid, :encontrada, %{especie: "gato", zona: "Bosque"})
      {:ok, perro: perro, gato: gato}
    end

    test "sin filtros devuelve todo ordenado por id", %{pid: pid} do
      assert {:ok, lista} = MascotasServer.consultar(pid, [])
      assert Enum.map(lista, & &1.id) == ["M001", "M002"]
    end

    test "filtra por especie sin distinguir mayúsculas", %{pid: pid} do
      assert {:ok, [mascota]} = MascotasServer.consultar(pid, especie: "GATO")
      assert mascota.id == "M002"
    end

    test "filtra por zona sin distinguir tildes", %{pid: pid} do
      reportar_ok(pid, :perdida, %{zona: "Montería"})
      assert {:ok, [mascota]} = MascotasServer.consultar(pid, zona: "monteria")
      assert mascota.id == "M003"
    end

    test "filtra por estado como átomo y como texto", %{pid: pid} do
      {:ok, _} = MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")
      reportar_ok(pid, :perdida)

      assert {:ok, activas} = MascotasServer.consultar(pid, estado: :activa)
      assert Enum.map(activas, & &1.id) == ["M003"]

      assert {:ok, posibles} = MascotasServer.consultar(pid, estado: "posible_coincidencia")
      assert Enum.map(posibles, & &1.id) == ["M001", "M002"]
    end

    test "combina filtros y acepta mapas", %{pid: pid} do
      assert {:ok, [mascota]} = MascotasServer.consultar(pid, %{especie: "perro", zona: "centro"})
      assert mascota.id == "M001"

      assert {:ok, []} = MascotasServer.consultar(pid, especie: "perro", zona: "Bosque")
    end

    test "un filtro nil se ignora", %{pid: pid} do
      assert {:ok, lista} = MascotasServer.consultar(pid, especie: nil, zona: nil, estado: nil)
      assert length(lista) == 2
    end

    test "filtros que no son keyword ni mapa", %{pid: pid} do
      assert {:error, :filtros_invalidos} = MascotasServer.consultar(pid, [1, 2])
      assert {:error, :filtros_invalidos} = MascotasServer.consultar(pid, "perro")
    end

    test "clave desconocida o valor que no es texto", %{pid: pid} do
      assert {:error, :filtro_invalido} = MascotasServer.consultar(pid, color: "marrón")
      assert {:error, :filtro_invalido} = MascotasServer.consultar(pid, especie: 5)
    end

    test "estado inexistente", %{pid: pid} do
      assert {:error, :estado_invalido} = MascotasServer.consultar(pid, estado: :volando)
      assert {:error, :estado_invalido} = MascotasServer.consultar(pid, estado: "volando")
    end
  end

  # ---------------------------------------------------------------------------
  # buscar_coincidencias/1
  # ---------------------------------------------------------------------------

  describe "buscar_coincidencias" do
    test "sin reportes devuelve lista vacía", %{pid: pid} do
      assert {:ok, []} = MascotasServer.buscar_coincidencias(pid)
    end

    test "encuentra una perdida y una encontrada con los mismos datos", %{pid: pid} do
      perdida = reportar_ok(pid, :perdida)
      encontrada = reportar_ok(pid, :encontrada)

      assert {:ok, [coincidencia]} = MascotasServer.buscar_coincidencias(pid)
      assert coincidencia.perdida_id == perdida.id
      assert coincidencia.encontrada_id == encontrada.id
      assert coincidencia.puntaje >= 60
    end

    test "no relaciona reportes muy distintos", %{pid: pid} do
      reportar_ok(pid, :perdida)

      reportar_ok(pid, :encontrada, %{
        especie: "loro",
        caracteristicas: "plumas verdes",
        color: "verde",
        tamano: :pequeno,
        zona: "Norte"
      })

      assert {:ok, []} = MascotasServer.buscar_coincidencias(pid)
    end

    test "ignora los reportes que ya no están activos", %{pid: pid} do
      reportar_ok(pid, :perdida)
      reportar_ok(pid, :encontrada)
      {:ok, _} = MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")

      assert {:ok, []} = MascotasServer.buscar_coincidencias(pid)
    end

    test "no cambia ningún estado", %{pid: pid} do
      reportar_ok(pid, :perdida)
      reportar_ok(pid, :encontrada)

      assert {:ok, [_ | _]} = MascotasServer.buscar_coincidencias(pid)
      assert {:ok, lista} = MascotasServer.consultar(pid, [])
      assert Enum.all?(lista, &(&1.estado == :activa))
    end
  end

  # ---------------------------------------------------------------------------
  # registrar_posible_coincidencia/3
  # ---------------------------------------------------------------------------

  describe "registrar_posible_coincidencia" do
    setup %{pid: pid} do
      perdida = reportar_ok(pid, :perdida)
      encontrada = reportar_ok(pid, :encontrada)
      {:ok, perdida: perdida, encontrada: encontrada}
    end

    test "pasa ambas de activa a posible_coincidencia", %{pid: pid} do
      assert {:ok, {perdida, encontrada}} =
               MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")

      assert perdida.id == "M001"
      assert perdida.estado == :posible_coincidencia
      assert encontrada.id == "M002"
      assert encontrada.estado == :posible_coincidencia

      assert {:ok, lista} = MascotasServer.consultar(pid, estado: :posible_coincidencia)
      assert length(lista) == 2
    end

    test "id inexistente", %{pid: pid} do
      assert {:error, :no_encontrada} =
               MascotasServer.registrar_posible_coincidencia(pid, "M999", "M002")

      assert {:error, :no_encontrada} =
               MascotasServer.registrar_posible_coincidencia(pid, "M001", "M999")
    end

    test "tipos invertidos o iguales", %{pid: pid} do
      reportar_ok(pid, :perdida)

      assert {:error, :tipos_invalidos} =
               MascotasServer.registrar_posible_coincidencia(pid, "M002", "M001")

      assert {:error, :tipos_invalidos} =
               MascotasServer.registrar_posible_coincidencia(pid, "M001", "M003")
    end

    test "transición inválida si alguna ya es posible coincidencia y no cambia ninguna", %{
      pid: pid
    } do
      {:ok, _} = MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")
      reportar_ok(pid, :encontrada)

      assert {:error, :transicion_invalida} =
               MascotasServer.registrar_posible_coincidencia(pid, "M001", "M003")

      assert {:ok, [tercera]} = MascotasServer.consultar(pid, especie: "perro", estado: :activa)
      assert tercera.id == "M003"
    end

    test "ya resuelta", %{pid: pid} do
      {:ok, _} = MascotasServer.confirmar_coincidencia(pid, "M001", "M002")

      assert {:error, :ya_resuelta} =
               MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")
    end
  end

  # ---------------------------------------------------------------------------
  # confirmar_coincidencia/3
  # ---------------------------------------------------------------------------

  describe "confirmar_coincidencia" do
    setup %{pid: pid} do
      reportar_ok(pid, :perdida)
      reportar_ok(pid, :encontrada)
      :ok
    end

    test "pasa ambas de activa a resuelta", %{pid: pid} do
      assert {:ok, {perdida, encontrada}} =
               MascotasServer.confirmar_coincidencia(pid, "M001", "M002")

      assert perdida.estado == :resuelta
      assert encontrada.estado == :resuelta
    end

    test "pasa ambas de posible_coincidencia a resuelta", %{pid: pid} do
      {:ok, _} = MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")

      assert {:ok, {perdida, encontrada}} =
               MascotasServer.confirmar_coincidencia(pid, "M001", "M002")

      assert perdida.estado == :resuelta
      assert encontrada.estado == :resuelta
    end

    test "id inexistente", %{pid: pid} do
      assert {:error, :no_encontrada} = MascotasServer.confirmar_coincidencia(pid, "M999", "M002")
      assert {:error, :no_encontrada} = MascotasServer.confirmar_coincidencia(pid, "M001", "M999")
    end

    test "tipos inválidos", %{pid: pid} do
      assert {:error, :tipos_invalidos} =
               MascotasServer.confirmar_coincidencia(pid, "M002", "M001")
    end

    test "ya resuelta devuelve error", %{pid: pid} do
      {:ok, _} = MascotasServer.confirmar_coincidencia(pid, "M001", "M002")

      assert {:error, :ya_resuelta} = MascotasServer.confirmar_coincidencia(pid, "M001", "M002")
    end

    test "si solo una está resuelta no se cambia ninguna (todo o nada)", %{pid: pid} do
      {:ok, _} = MascotasServer.confirmar_coincidencia(pid, "M001", "M002")
      reportar_ok(pid, :encontrada)

      assert {:error, :ya_resuelta} = MascotasServer.confirmar_coincidencia(pid, "M001", "M003")

      assert {:ok, [nueva]} = MascotasServer.consultar(pid, estado: :activa)
      assert nueva.id == "M003"
    end
  end

  # ---------------------------------------------------------------------------
  # Persistencia
  # ---------------------------------------------------------------------------

  describe "persistencia" do
    test "un servidor nuevo recupera los reportes y continúa los ids", %{pid: pid} do
      reportar_ok(pid, :perdida)
      reportar_ok(pid, :encontrada)
      {:ok, _} = MascotasServer.confirmar_coincidencia(pid, "M001", "M002")

      otro = iniciar(:servidor_recargado)

      assert {:ok, lista} = MascotasServer.consultar(otro, [])
      assert Enum.map(lista, & &1.id) == ["M001", "M002"]
      assert Enum.all?(lista, &(&1.estado == :resuelta))
      assert reportar_ok(otro, :perdida).id == "M003"
    end

    test "los cambios de estado de una pareja se guardan", %{pid: pid} do
      reportar_ok(pid, :perdida)
      reportar_ok(pid, :encontrada)
      {:ok, _} = MascotasServer.registrar_posible_coincidencia(pid, "M001", "M002")

      otro = iniciar(:servidor_recargado)

      assert {:ok, lista} = MascotasServer.consultar(otro, estado: :posible_coincidencia)
      assert length(lista) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp iniciar(id) do
    spec = %{id: id, start: {MascotasServer, :start_link, [[name: nil]]}}
    {:ok, pid} = start_supervised(spec)
    pid
  end

  defp reportar(pid, tipo, cambios) do
    d = Map.merge(@datos_base, cambios)

    MascotasServer.reportar(
      pid,
      tipo,
      d.especie,
      d.nombre,
      d.caracteristicas,
      d.color,
      d.tamano,
      d.zona,
      d.contacto
    )
  end

  defp reportar_ok(pid, tipo, cambios \\ %{}) do
    {:ok, mascota} = reportar(pid, tipo, cambios)
    mascota
  end
end
