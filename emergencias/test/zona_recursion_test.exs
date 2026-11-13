defmodule Emergencias.Dominio.ZonaRecursionTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Dominio.Sector
  alias Emergencias.Dominio.Zona

  # Zona de prueba (estimadas = 1000, independiente de la suma):
  #
  #   S1 (10 personas)
  #     P1 (5)
  #     P2 (3)
  #   S2 (20 personas)
  #     P3 (7)
  #
  # Total esperado: 10 + 5 + 3 + 20 + 7 = 45
  defp zona_con_jerarquia do
    s1 = sector("S1", 10, [punto("P1", 5), punto("P2", 3)])
    s2 = sector("S2", 20, [punto("P3", 7)])
    zona("centro", 1000, [s1, s2])
  end

  defp punto(codigo, personas) do
    {:ok, punto} = PuntoAtencion.crear(codigo, "Punto " <> codigo, personas)
    punto
  end

  defp sector(codigo, personas, puntos) do
    {:ok, sector} = Sector.crear(codigo, "Sector " <> codigo, personas)
    %Sector{sector | puntos_atencion: puntos}
  end

  defp zona(codigo, estimadas, sectores) do
    {:ok, zona} = Zona.crear(codigo, "Zona " <> codigo, :critico, estimadas)
    %Zona{zona | sectores: sectores}
  end

  describe "total_personas/1" do
    test "suma sectores y puntos de una zona con 2 sectores y 3 puntos" do
      assert Zona.total_personas(zona_con_jerarquia()) == 45
    end

    test "no incluye la estimación de la zona" do
      zona = zona("centro", 9999, [sector("S1", 4, [])])

      assert Zona.total_personas(zona) == 4
    end

    test "una zona sin sectores suma 0 aunque tenga estimación" do
      assert Zona.total_personas(zona("centro", 500, [])) == 0
    end

    test "un sector sin puntos aporta solo sus personas" do
      zona = zona("centro", 0, [sector("S1", 10, []), sector("S2", 6, [])])

      assert Zona.total_personas(zona) == 16
    end

    test "un sector con 0 personas aún suma las de sus puntos" do
      zona = zona("centro", 0, [sector("S1", 0, [punto("P1", 8)])])

      assert Zona.total_personas(zona) == 8
    end

    test "funciona con una jerarquía grande" do
      puntos = for n <- 1..50_000, do: punto("P#{n}", 1)
      zona = zona("centro", 0, [sector("S1", 5, puntos)])

      assert Zona.total_personas(zona) == 50_005
    end
  end

  describe "buscar_nodo/2" do
    test "encuentra un sector por su código" do
      zona = zona_con_jerarquia()

      assert {:ok, {:sector, %Sector{codigo: "S2", personas_afectadas: 20}}} =
               Zona.buscar_nodo(zona, "S2")
    end

    test "encuentra un punto de atención en el primer sector" do
      assert {:ok, {:punto, %PuntoAtencion{codigo: "P2", personas_afectadas: 3}}} =
               Zona.buscar_nodo(zona_con_jerarquia(), "P2")
    end

    test "encuentra un punto de atención en un sector posterior" do
      assert {:ok, {:punto, %PuntoAtencion{codigo: "P3", personas_afectadas: 7}}} =
               Zona.buscar_nodo(zona_con_jerarquia(), "P3")
    end

    test "devuelve la misma struct que está dentro de la zona" do
      zona = zona_con_jerarquia()
      [s1, _s2] = zona.sectores
      [p1, _p2] = s1.puntos_atencion

      assert {:ok, {:sector, ^s1}} = Zona.buscar_nodo(zona, "S1")
      assert {:ok, {:punto, ^p1}} = Zona.buscar_nodo(zona, "P1")
    end

    test "devuelve :no_encontrado con un código inexistente" do
      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona_con_jerarquia(), "X99")
    end

    test "distingue mayúsculas y no recorta espacios" do
      zona = zona_con_jerarquia()

      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, "s1")
      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, " S1 ")
    end

    test "devuelve :no_encontrado si el código no es texto" do
      zona = zona_con_jerarquia()

      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, nil)
      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, :S1)
      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, 1)
    end

    test "devuelve :no_encontrado en una zona sin sectores" do
      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona("centro", 0, []), "S1")
    end

    test "devuelve :no_encontrado en un sector sin puntos" do
      zona = zona("centro", 0, [sector("S1", 1, [])])

      assert {:error, :no_encontrado} = Zona.buscar_nodo(zona, "P1")
    end

    test "con un punto repetido en dos sectores gana el primero en el recorrido" do
      s1 = sector("S1", 0, [punto("P1", 1)])
      s2 = sector("S2", 0, [punto("P1", 2)])
      zona = zona("centro", 0, [s1, s2])

      assert {:ok, {:punto, %PuntoAtencion{personas_afectadas: 1}}} = Zona.buscar_nodo(zona, "P1")
    end

    test "con un sector y un punto con el mismo código gana el sector si va primero" do
      s1 = sector("X", 3, [])
      s2 = sector("S2", 0, [punto("X", 9)])
      zona = zona("centro", 0, [s1, s2])

      assert {:ok, {:sector, %Sector{codigo: "X", personas_afectadas: 3}}} =
               Zona.buscar_nodo(zona, "X")
    end
  end

  describe "aplanar/1" do
    test "lista cada sector seguido de sus puntos" do
      assert Zona.aplanar(zona_con_jerarquia()) == [
               {:sector, "S1", "Sector S1", 10},
               {:punto, "P1", "Punto P1", 5},
               {:punto, "P2", "Punto P2", 3},
               {:sector, "S2", "Sector S2", 20},
               {:punto, "P3", "Punto P3", 7}
             ]
    end

    test "una zona sin sectores devuelve lista vacía" do
      assert Zona.aplanar(zona("centro", 500, [])) == []
    end

    test "un sector sin puntos aparece solo" do
      zona = zona("centro", 0, [sector("S1", 2, [])])

      assert Zona.aplanar(zona) == [{:sector, "S1", "Sector S1", 2}]
    end

    test "la cantidad de tuplas es sectores más puntos" do
      assert length(Zona.aplanar(zona_con_jerarquia())) == 5
    end
  end

  describe "estadisticas/1" do
    test "calcula todas las claves en una zona con 2 sectores y 3 puntos" do
      assert Zona.estadisticas(zona_con_jerarquia()) == %{
               total_personas: 45,
               estimadas: 1000,
               num_sectores: 2,
               num_puntos: 3,
               por_sector: [
                 %{codigo: "S1", total: 18},
                 %{codigo: "S2", total: 27}
               ]
             }
    end

    test "una zona sin sectores tiene todo en cero y por_sector vacío" do
      assert Zona.estadisticas(zona("centro", 300, [])) == %{
               total_personas: 0,
               estimadas: 300,
               num_sectores: 0,
               num_puntos: 0,
               por_sector: []
             }
    end

    test "un sector sin puntos cuenta como sector y su total es el propio" do
      zona = zona("centro", 0, [sector("S1", 12, [])])

      assert %{num_sectores: 1, num_puntos: 0, por_sector: [%{codigo: "S1", total: 12}]} =
               Zona.estadisticas(zona)
    end

    test "total_personas coincide con total_personas/1 y con la suma de por_sector" do
      zona = zona_con_jerarquia()
      estadisticas = Zona.estadisticas(zona)

      assert estadisticas.total_personas == Zona.total_personas(zona)
      assert estadisticas.total_personas == 18 + 27
    end

    test "por_sector conserva el orden de los sectores de la zona" do
      zona = zona("centro", 0, [sector("B", 1, []), sector("A", 2, []), sector("C", 3, [])])

      codigos = Zona.estadisticas(zona).por_sector |> Enum.map(& &1.codigo)
      assert codigos == ["B", "A", "C"]
    end
  end
end
