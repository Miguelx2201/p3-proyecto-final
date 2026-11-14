defmodule Emergencias.Servicios.NecesidadesServicioTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Fabrica
  alias Emergencias.Servicios.NecesidadesServicio

  # Necesidad de prueba: parte de la fábrica y sobrescribe los campos dados
  # (sin pasar por la máquina de estados, solo para armar casos).
  defp nec(id, campos \\ []) do
    Map.merge(Fabrica.necesidad(), Map.new([{:id, id} | campos]))
  end

  defp ids(necesidades), do: Enum.map(necesidades, & &1.id)

  # Colección variada para los filtros.
  defp coleccion do
    [
      nec("N001", zona: "centro", tipo: :agua, prioridad: :critica, estado: :pendiente),
      nec("N002", zona: "centro", tipo: :alimentos, prioridad: :alta, estado: :asignada),
      nec("N003", zona: "norte", tipo: :agua, prioridad: :alta, estado: :pendiente),
      nec("N004", zona: "norte", tipo: :rescate, prioridad: :media, estado: :en_atencion),
      nec("N005", zona: "sur", tipo: :agua, prioridad: :baja, estado: :cancelada),
      nec("N006", zona: "centro", tipo: :agua, prioridad: :critica, estado: :atendida)
    ]
  end

  describe "filtrar/2" do
    test "lista vacía devuelve lista vacía" do
      assert NecesidadesServicio.filtrar([], zona: "centro") == []
      assert NecesidadesServicio.filtrar([], []) == []
    end

    test "sin filtros devuelve todo, en el mismo orden" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), [])) ==
               ["N001", "N002", "N003", "N004", "N005", "N006"]
    end

    test "filtra por zona" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), zona: "norte")) == ["N003", "N004"]
    end

    test "filtra por tipo" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), tipo: :rescate)) == ["N004"]

      assert ids(NecesidadesServicio.filtrar(coleccion(), tipo: :agua)) ==
               ["N001", "N003", "N005", "N006"]
    end

    test "filtra por prioridad" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), prioridad: :alta)) == ["N002", "N003"]
    end

    test "filtra por estado" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), estado: :pendiente)) ==
               ["N001", "N003"]
    end

    test "combina dos filtros (deben cumplirse ambos)" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), zona: "centro", tipo: :agua)) ==
               ["N001", "N006"]
    end

    test "combina los cuatro filtros" do
      filtros = [zona: "centro", tipo: :agua, prioridad: :critica, estado: :pendiente]
      assert ids(NecesidadesServicio.filtrar(coleccion(), filtros)) == ["N001"]
    end

    test "el orden de las claves no importa" do
      a = NecesidadesServicio.filtrar(coleccion(), zona: "centro", estado: :pendiente)
      b = NecesidadesServicio.filtrar(coleccion(), estado: :pendiente, zona: "centro")
      assert a == b
      assert ids(a) == ["N001"]
    end

    test "si nada coincide devuelve lista vacía" do
      assert NecesidadesServicio.filtrar(coleccion(), zona: "centro", tipo: :rescate) == []
      assert NecesidadesServicio.filtrar(coleccion(), zona: "inexistente") == []
      assert NecesidadesServicio.filtrar(coleccion(), estado: :volando) == []
    end

    test "una clave de filtro desconocida se ignora" do
      assert ids(NecesidadesServicio.filtrar(coleccion(), color: :rojo, zona: "sur")) ==
               ["N005"]
    end
  end

  describe "ordenar_por_prioridad/1" do
    test "lista vacía devuelve lista vacía" do
      assert NecesidadesServicio.ordenar_por_prioridad([]) == []
    end

    test "un elemento devuelve la misma lista" do
      n = nec("N001")
      assert NecesidadesServicio.ordenar_por_prioridad([n]) == [n]
    end

    test "prioridades mezcladas: crítica, alta, media, baja" do
      lista = [
        nec("N001", prioridad: :baja),
        nec("N002", prioridad: :critica),
        nec("N003", prioridad: :media),
        nec("N004", prioridad: :alta)
      ]

      assert ids(NecesidadesServicio.ordenar_por_prioridad(lista)) ==
               ["N002", "N004", "N003", "N001"]
    end

    test "con la misma prioridad va primero la más antigua" do
      lista = [
        nec("N001", prioridad: :alta, fecha: "2026-01-01T10:00:00Z"),
        nec("N002", prioridad: :alta, fecha: "2026-01-01T08:00:00Z"),
        nec("N003", prioridad: :alta, fecha: "2026-01-01T09:00:00Z")
      ]

      assert ids(NecesidadesServicio.ordenar_por_prioridad(lista)) ==
               ["N002", "N003", "N001"]
    end

    test "la prioridad pesa más que la antigüedad" do
      lista = [
        nec("N001", prioridad: :baja, fecha: "2026-01-01T00:00:00Z"),
        nec("N002", prioridad: :critica, fecha: "2026-01-02T00:00:00Z")
      ]

      assert ids(NecesidadesServicio.ordenar_por_prioridad(lista)) == ["N002", "N001"]
    end

    test "empate de prioridad y de fecha conserva el orden de entrada" do
      lista = [
        nec("N001", prioridad: :media),
        nec("N002", prioridad: :media),
        nec("N003", prioridad: :media)
      ]

      assert ids(NecesidadesServicio.ordenar_por_prioridad(lista)) == ["N001", "N002", "N003"]
    end

    test "combina prioridad y fecha en una misma lista" do
      lista = [
        nec("N001", prioridad: :media, fecha: "2026-01-01T01:00:00Z"),
        nec("N002", prioridad: :critica, fecha: "2026-01-01T05:00:00Z"),
        nec("N003", prioridad: :media, fecha: "2026-01-01T00:00:00Z"),
        nec("N004", prioridad: :critica, fecha: "2026-01-01T03:00:00Z")
      ]

      assert ids(NecesidadesServicio.ordenar_por_prioridad(lista)) ==
               ["N004", "N002", "N003", "N001"]
    end

    test "no pierde ni duplica elementos y no los modifica" do
      lista = coleccion()
      ordenada = NecesidadesServicio.ordenar_por_prioridad(lista)

      assert length(ordenada) == length(lista)
      assert Enum.sort_by(ordenada, & &1.id) == lista
    end
  end

  describe "pendientes/1" do
    test "lista vacía devuelve lista vacía" do
      assert NecesidadesServicio.pendientes([]) == []
    end

    test "devuelve solo las pendientes, ordenadas por prioridad" do
      lista = [
        nec("N001", estado: :pendiente, prioridad: :baja),
        nec("N002", estado: :asignada, prioridad: :critica),
        nec("N003", estado: :pendiente, prioridad: :critica),
        nec("N004", estado: :atendida, prioridad: :critica),
        nec("N005", estado: :cancelada, prioridad: :alta),
        nec("N006", estado: :en_atencion, prioridad: :alta),
        nec("N007", estado: :pendiente, prioridad: :alta)
      ]

      assert ids(NecesidadesServicio.pendientes(lista)) == ["N003", "N007", "N001"]
    end

    test "si no hay pendientes devuelve lista vacía" do
      lista = [nec("N001", estado: :asignada), nec("N002", estado: :cancelada)]
      assert NecesidadesServicio.pendientes(lista) == []
    end
  end

  describe "siguiente_a_atender/1" do
    test "lista vacía devuelve :sin_pendientes" do
      assert {:error, :sin_pendientes} = NecesidadesServicio.siguiente_a_atender([])
    end

    test "sin ninguna pendiente devuelve :sin_pendientes" do
      lista = [nec("N001", estado: :en_atencion), nec("N002", estado: :atendida)]
      assert {:error, :sin_pendientes} = NecesidadesServicio.siguiente_a_atender(lista)
    end

    test "con una sola pendiente la devuelve" do
      n = nec("N001")
      assert {:ok, ^n} = NecesidadesServicio.siguiente_a_atender([n])
    end

    test "devuelve la pendiente de mayor prioridad" do
      lista = [
        nec("N001", prioridad: :media),
        nec("N002", prioridad: :critica, estado: :asignada),
        nec("N003", prioridad: :alta)
      ]

      assert {:ok, %Necesidad{id: "N003"}} = NecesidadesServicio.siguiente_a_atender(lista)
    end

    test "ante igual prioridad devuelve la más antigua" do
      lista = [
        nec("N001", prioridad: :critica, fecha: "2026-01-01T12:00:00Z"),
        nec("N002", prioridad: :critica, fecha: "2026-01-01T06:00:00Z")
      ]

      assert {:ok, %Necesidad{id: "N002"}} = NecesidadesServicio.siguiente_a_atender(lista)
    end
  end
end
