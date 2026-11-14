defmodule Emergencias.Servicios.ReportesServicioTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Sector
  alias Emergencias.Dominio.Zona
  alias Emergencias.Servicios.ReportesServicio

  # ---------------------------------------------------------------------------
  # Datos de prueba
  # ---------------------------------------------------------------------------

  defp albergue(id, capacidad, ocupacion) do
    {:ok, albergue} = Albergue.crear(id, "Albergue #{id}", "centro", capacidad, ocupacion)
    albergue
  end

  defp recurso(id, categoria, cantidad, zona) do
    {:ok, recurso} =
      Recurso.crear(id, "Recurso #{id}", categoria, cantidad, "unidades", "bodega", zona)

    recurso
  end

  defp necesidad(id, tipo, cantidad, zona, prioridad \\ :media) do
    {:ok, necesidad} =
      Necesidad.crear(id, tipo, nil, "Necesidad #{id}", cantidad, zona, prioridad, "laura")

    necesidad
  end

  defp avanzar(necesidad, estados) do
    Enum.reduce(estados, necesidad, fn estado, actual ->
      {:ok, siguiente} = Necesidad.cambiar_estado(actual, estado)
      siguiente
    end)
  end

  defp persona(documento, estado) do
    {:ok, persona} =
      Persona.crear(documento, "Persona #{documento}", 30, "centro", estado, "laura")

    persona
  end

  defp mensaje(id, entregado?) do
    {:ok, mensaje} = Mensaje.crear(id, "laura", "1094", "Estamos bien")

    if entregado? do
      {:ok, entregado} = Mensaje.marcar_entregado(mensaje)
      entregado
    else
      mensaje
    end
  end

  defp mascota(id, estados) do
    {:ok, mascota} =
      Mascota.crear(
        id,
        :perdida,
        "perro",
        "Max",
        "collar rojo",
        "negro",
        :mediano,
        "centro",
        "300"
      )

    Enum.reduce(estados, mascota, fn estado, actual ->
      {:ok, siguiente} = Mascota.cambiar_estado(actual, estado)
      siguiente
    end)
  end

  # Zona "centro" con un sector de 10 personas que tiene dos puntos (5 y 3).
  defp zona_con_jerarquia do
    {:ok, zona} = Zona.crear("centro", "Centro", :critico, 500)
    {:ok, sector} = Sector.crear("S1", "Sector 1", 10)
    {:ok, punto_a} = PuntoAtencion.crear("P1", "Punto 1", 5)
    {:ok, punto_b} = PuntoAtencion.crear("P2", "Punto 2", 3)
    {:ok, sector} = Sector.agregar_punto(sector, punto_a)
    {:ok, sector} = Sector.agregar_punto(sector, punto_b)
    {:ok, zona} = Zona.agregar_sector(zona, sector)
    zona
  end

  defp ids(lista), do: Enum.map(lista, & &1.id)

  # ---------------------------------------------------------------------------
  # albergues_mas_ocupados/2
  # ---------------------------------------------------------------------------

  describe "albergues_mas_ocupados/2" do
    test "ordena de mayor a menor porcentaje de ocupación" do
      albergues = [albergue("A1", 100, 50), albergue("A2", 10, 9), albergue("A3", 10, 1)]

      assert ids(ReportesServicio.albergues_mas_ocupados(albergues)) == ["A2", "A1", "A3"]
    end

    test "toma solo los primeros n" do
      albergues = [albergue("A1", 100, 50), albergue("A2", 10, 9), albergue("A3", 10, 1)]

      assert ids(ReportesServicio.albergues_mas_ocupados(albergues, 2)) == ["A2", "A1"]
    end

    test "por defecto devuelve como máximo 5" do
      albergues = for i <- 1..7, do: albergue("A#{i}", 10, i)

      resultado = ReportesServicio.albergues_mas_ocupados(albergues)

      assert ids(resultado) == ["A7", "A6", "A5", "A4", "A3"]
    end

    test "si hay menos de n devuelve todos" do
      albergues = [albergue("A1", 10, 2), albergue("A2", 10, 8)]

      assert ids(ReportesServicio.albergues_mas_ocupados(albergues, 10)) == ["A2", "A1"]
    end

    test "con el mismo porcentaje conserva el orden de entrada" do
      albergues = [albergue("A1", 10, 5), albergue("A2", 20, 10), albergue("A3", 4, 2)]

      assert ids(ReportesServicio.albergues_mas_ocupados(albergues)) == ["A1", "A2", "A3"]
    end

    test "un albergue con capacidad 0 cuenta como 0 % y va al final" do
      albergues = [albergue("A0", 0, 0), albergue("A1", 10, 1)]

      assert ids(ReportesServicio.albergues_mas_ocupados(albergues)) == ["A1", "A0"]
    end

    test "con n = 0 devuelve []" do
      assert ReportesServicio.albergues_mas_ocupados([albergue("A1", 10, 5)], 0) == []
    end

    test "con lista vacía devuelve []" do
      assert ReportesServicio.albergues_mas_ocupados([]) == []
    end

    test "un n negativo no se acepta" do
      assert_raise FunctionClauseError, fn ->
        ReportesServicio.albergues_mas_ocupados([], -1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # disponibilidad/3
  # ---------------------------------------------------------------------------

  describe "disponibilidad/3" do
    test "suma solo los recursos de la categoría y la zona pedidas" do
      recursos = [
        recurso("R1", :agua, 10, "centro"),
        recurso("R2", :agua, 5, "centro"),
        recurso("R3", :agua, 7, "norte"),
        recurso("R4", :alimentos, 3, "centro")
      ]

      assert ReportesServicio.disponibilidad(recursos, :agua, "centro") == 15
    end

    test "sin coincidencias devuelve 0" do
      recursos = [recurso("R1", :agua, 10, "centro")]

      assert ReportesServicio.disponibilidad(recursos, :medicamentos, "centro") == 0
      assert ReportesServicio.disponibilidad(recursos, :agua, "sur") == 0
    end

    test "con lista vacía devuelve 0" do
      assert ReportesServicio.disponibilidad([], :agua, "centro") == 0
    end
  end

  # ---------------------------------------------------------------------------
  # recursos_criticos/2
  # ---------------------------------------------------------------------------

  describe "recursos_criticos/2" do
    test "marca crítico un par cuyo disponible es menor que la demanda" do
      recursos = [recurso("R1", :agua, 30, "centro")]

      necesidades = [
        necesidad("N1", :agua, 50, "centro"),
        necesidad("N2", :agua, 20, "centro")
      ]

      assert ReportesServicio.recursos_criticos(recursos, necesidades) == [
               %{zona: "centro", categoria: :agua, disponible: 30, demanda: 70, deficit: 40}
             ]
    end

    test "no es crítico si el disponible es igual a la demanda" do
      recursos = [recurso("R1", :agua, 50, "centro")]
      necesidades = [necesidad("N1", :agua, 50, "centro")]

      assert ReportesServicio.recursos_criticos(recursos, necesidades) == []
    end

    test "no es crítico si el disponible supera la demanda" do
      recursos = [recurso("R1", :agua, 80, "centro")]
      necesidades = [necesidad("N1", :agua, 50, "centro")]

      assert ReportesServicio.recursos_criticos(recursos, necesidades) == []
    end

    test "ignora las necesidades atendidas y canceladas" do
      atendida =
        necesidad("N1", :agua, 100, "centro")
        |> avanzar([:asignada, :en_atencion, :atendida])

      cancelada = necesidad("N2", :agua, 100, "centro") |> avanzar([:cancelada])

      assert ReportesServicio.recursos_criticos([], [atendida, cancelada]) == []
    end

    test "cuenta las necesidades asignadas y en atención que aún tienen faltante" do
      asignada = necesidad("N1", :agua, 10, "centro") |> avanzar([:asignada])
      en_atencion = necesidad("N2", :agua, 5, "centro") |> avanzar([:asignada, :en_atencion])

      assert [%{demanda: 15}] = ReportesServicio.recursos_criticos([], [asignada, en_atencion])
    end

    test "la demanda usa la cantidad faltante, no la requerida" do
      {:ok, parcial} = Necesidad.registrar_asignacion(necesidad("N1", :agua, 50, "centro"), 30)

      assert [%{demanda: 20, disponible: 10, deficit: 10}] =
               ReportesServicio.recursos_criticos([recurso("R1", :agua, 10, "centro")], [parcial])
    end

    test "una necesidad totalmente asignada no genera demanda" do
      {:ok, cubierta} = Necesidad.registrar_asignacion(necesidad("N1", :agua, 50, "centro"), 50)

      assert ReportesServicio.recursos_criticos([], [cubierta]) == []
    end

    test "los recursos de otra zona o categoría no cubren la demanda" do
      recursos = [recurso("R1", :agua, 100, "norte"), recurso("R2", :alimentos, 100, "centro")]
      necesidades = [necesidad("N1", :agua, 10, "centro")]

      assert ReportesServicio.recursos_criticos(recursos, necesidades) == [
               %{zona: "centro", categoria: :agua, disponible: 0, demanda: 10, deficit: 10}
             ]
    end

    test "ordena de mayor a menor déficit y desempata por zona y categoría" do
      necesidades = [
        necesidad("N1", :agua, 5, "sur"),
        necesidad("N2", :medicamentos, 20, "centro"),
        necesidad("N3", :alimentos, 5, "centro"),
        necesidad("N4", :agua, 5, "centro")
      ]

      resultado = ReportesServicio.recursos_criticos([], necesidades)

      assert Enum.map(resultado, &{&1.zona, &1.categoria}) == [
               {"centro", :medicamentos},
               {"centro", :agua},
               {"centro", :alimentos},
               {"sur", :agua}
             ]
    end

    test "con listas vacías devuelve []" do
      assert ReportesServicio.recursos_criticos([], []) == []
      assert ReportesServicio.recursos_criticos([recurso("R1", :agua, 10, "centro")], []) == []
    end
  end

  # ---------------------------------------------------------------------------
  # resumen_global/1
  # ---------------------------------------------------------------------------

  describe "resumen_global/1" do
    test "resume un conjunto pequeño de datos" do
      datos = %{
        zonas: [zona_con_jerarquia()],
        necesidades: [
          necesidad("N1", :agua, 10, "centro", :critica),
          necesidad("N2", :agua, 10, "centro", :critica),
          necesidad("N3", :alimentos, 10, "centro", :baja),
          necesidad("N4", :agua, 10, "centro", :alta) |> avanzar([:asignada]),
          necesidad("N5", :agua, 10, "centro", :media) |> avanzar([:cancelada])
        ],
        recursos: [
          recurso("R1", :agua, 10, "centro"),
          recurso("R2", :agua, 5, "norte"),
          recurso("R3", :medicamentos, 7, "centro")
        ],
        personas: [
          persona("1", :sin_informacion),
          persona("2", :reportada),
          persona("3", :localizada),
          persona("4", :trasladada),
          persona("5", :en_albergue),
          persona("6", :reunificada)
        ],
        mensajes: [mensaje("MS1", false), mensaje("MS2", true), mensaje("MS3", false)],
        mascotas: [
          mascota("M1", []),
          mascota("M2", []),
          mascota("M3", [:posible_coincidencia]),
          mascota("M4", [:resuelta])
        ],
        albergues: [albergue("A1", 100, 40), albergue("A2", 50, 50)]
      }

      resumen = ReportesServicio.resumen_global(datos)

      assert resumen.recursos_por_categoria == %{
               agua: 15,
               alimentos: 0,
               medicamentos: 7,
               primeros_auxilios: 0,
               refugio: 0,
               transporte: 0,
               rescate: 0,
               otra: 0
             }

      assert resumen.necesidades_pendientes == %{critica: 2, alta: 0, media: 0, baja: 1}
      assert resumen.personas_localizadas == 4
      assert resumen.mensajes == %{total: 3, pendientes: 2}
      assert resumen.mascotas == %{activas: 2, posibles: 1, resueltas: 1}
      assert resumen.albergues == %{capacidad_total: 150, ocupacion_total: 90}

      assert resumen.zonas == [
               %{codigo: "centro", nombre: "Centro", nivel: :critico, personas: 18}
             ]
    end

    test "las personas de una zona no incluyen su estimación personas_afectadas" do
      {:ok, zona} = Zona.crear("norte", "Norte", :bajo, 1000)

      assert [%{personas: 0}] = ReportesServicio.resumen_global(%{zonas: [zona]}).zonas
    end

    test "con todas las listas vacías devuelve ceros" do
      datos = %{
        zonas: [],
        necesidades: [],
        recursos: [],
        personas: [],
        mensajes: [],
        mascotas: [],
        albergues: []
      }

      resumen = ReportesServicio.resumen_global(datos)

      assert Enum.all?(resumen.recursos_por_categoria, fn {_categoria, total} -> total == 0 end)
      assert map_size(resumen.recursos_por_categoria) == length(Recurso.categorias())
      assert resumen.necesidades_pendientes == %{critica: 0, alta: 0, media: 0, baja: 0}
      assert resumen.personas_localizadas == 0
      assert resumen.mensajes == %{total: 0, pendientes: 0}
      assert resumen.mascotas == %{activas: 0, posibles: 0, resueltas: 0}
      assert resumen.albergues == %{capacidad_total: 0, ocupacion_total: 0}
      assert resumen.zonas == []
    end

    test "una clave que falta se toma como lista vacía" do
      assert ReportesServicio.resumen_global(%{}) ==
               ReportesServicio.resumen_global(%{
                 zonas: [],
                 necesidades: [],
                 recursos: [],
                 personas: [],
                 mensajes: [],
                 mascotas: [],
                 albergues: []
               })
    end
  end
end
