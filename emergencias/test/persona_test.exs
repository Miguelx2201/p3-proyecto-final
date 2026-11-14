defmodule Emergencias.Dominio.PersonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.CSV
  alias Emergencias.Dominio.Persona
  alias Emergencias.Fabrica

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  defp crear_valida(atributos \\ []) do
    datos =
      Keyword.merge(
        [
          documento: "1094",
          nombre: "Andrés",
          edad: 30,
          zona: "centro",
          estado: :localizada,
          usuario: "laura"
        ],
        atributos
      )

    Persona.crear(
      datos[:documento],
      datos[:nombre],
      datos[:edad],
      datos[:zona],
      datos[:estado],
      datos[:usuario]
    )
  end

  # Quita la fecha para comparar el historial sin depender del reloj.
  defp resumen_historial(persona),
    do: Enum.map(persona.historial, fn e -> {e.de, e.a, e.usuario} end)

  describe "estados/0" do
    test "devuelve los estados en el orden de avance" do
      assert Persona.estados() == @estados
    end
  end

  describe "crear/6" do
    test "crea la persona y registra el estado inicial como primer elemento del historial" do
      assert {:ok, persona} = crear_valida()

      assert %Persona{
               documento: "1094",
               nombre: "Andrés",
               edad: 30,
               zona: "centro",
               estado: :localizada
             } = persona

      assert [%{fecha: fecha, de: nil, a: :localizada, usuario: "laura"}] = persona.historial
      assert {:ok, _fecha, 0} = DateTime.from_iso8601(fecha)
    end

    test "acepta cualquier estado inicial permitido" do
      for estado <- @estados do
        assert {:ok, %Persona{estado: ^estado, historial: [%{de: nil, a: ^estado}]}} =
                 crear_valida(estado: estado)
      end
    end

    test "acepta las edades límite 0 y 120" do
      assert {:ok, %Persona{edad: 0}} = crear_valida(edad: 0)
      assert {:ok, %Persona{edad: 120}} = crear_valida(edad: 120)
    end

    test "quita espacios de los extremos y los ; de los textos" do
      assert {:ok, persona} =
               crear_valida(documento: " 1094 ", nombre: "Ana; María ", zona: " centro ")

      assert persona.documento == "1094"
      assert persona.nombre == "Ana  María"
      assert persona.zona == "centro"
    end

    test "rechaza documento vacío, solo espacios o que no sea texto" do
      assert {:error, :documento_vacio} = crear_valida(documento: "")
      assert {:error, :documento_vacio} = crear_valida(documento: "   ")
      assert {:error, :documento_vacio} = crear_valida(documento: nil)
      assert {:error, :documento_vacio} = crear_valida(documento: 1094)
    end

    test "rechaza nombre vacío" do
      assert {:error, :nombre_vacio} = crear_valida(nombre: "")
      assert {:error, :nombre_vacio} = crear_valida(nombre: nil)
    end

    test "rechaza zona vacía" do
      assert {:error, :zona_vacia} = crear_valida(zona: " ")
      assert {:error, :zona_vacia} = crear_valida(zona: nil)
    end

    test "rechaza usuario vacío" do
      assert {:error, :usuario_vacio} = crear_valida(usuario: "")
      assert {:error, :usuario_vacio} = crear_valida(usuario: nil)
    end

    test "rechaza edad negativa, mayor que 120 o que no sea entera" do
      assert {:error, :edad_invalida} = crear_valida(edad: -1)
      assert {:error, :edad_invalida} = crear_valida(edad: 121)
      assert {:error, :edad_invalida} = crear_valida(edad: 30.0)
      assert {:error, :edad_invalida} = crear_valida(edad: "30")
      assert {:error, :edad_invalida} = crear_valida(edad: nil)
    end

    test "rechaza un estado que no está permitido" do
      assert {:error, :estado_invalido} = crear_valida(estado: :desaparecida)
      assert {:error, :estado_invalido} = crear_valida(estado: "localizada")
      assert {:error, :estado_invalido} = crear_valida(estado: nil)
    end
  end

  describe "cambiar_estado/3" do
    test "avanza al estado siguiente y agrega la entrada al historial" do
      {:ok, persona} = crear_valida(estado: :localizada)

      assert {:ok, cambiada} = Persona.cambiar_estado(persona, :trasladada, "pedro")
      assert cambiada.estado == :trasladada

      assert [%{fecha: fecha, de: :localizada, a: :trasladada, usuario: "pedro"}, _inicial] =
               cambiada.historial

      assert is_binary(fecha)
    end

    test "cada paso consecutivo del orden es válido" do
      pares = Enum.zip(@estados, tl(@estados))

      for {de, a} <- pares do
        persona = Fabrica.persona(estado: de)
        assert {:ok, %Persona{estado: ^a}} = Persona.cambiar_estado(persona, a, "laura")
      end
    end

    test "permite saltar hacia adelante" do
      persona = Fabrica.persona(estado: :reportada)

      assert {:ok,
              %Persona{estado: :en_albergue, historial: [%{de: :reportada, a: :en_albergue}]}} =
               Persona.cambiar_estado(persona, :en_albergue, "laura")

      persona = Fabrica.persona(estado: :sin_informacion)

      assert {:ok, %Persona{estado: :reunificada}} =
               Persona.cambiar_estado(persona, :reunificada, "laura")
    end

    test "retroceder a cualquier estado anterior es inválido" do
      for {de, i} <- Enum.with_index(@estados), {a, j} <- Enum.with_index(@estados), j < i do
        persona = Fabrica.persona(estado: de)
        assert {:error, :transicion_invalida} = Persona.cambiar_estado(persona, a, "laura")
      end
    end

    test "cambiar al mismo estado es un error" do
      for estado <- @estados do
        persona = Fabrica.persona(estado: estado)
        assert {:error, :mismo_estado} = Persona.cambiar_estado(persona, estado, "laura")
      end
    end

    test "rechaza un estado desconocido" do
      persona = Fabrica.persona()
      assert {:error, :estado_invalido} = Persona.cambiar_estado(persona, :perdida, "laura")
      assert {:error, :estado_invalido} = Persona.cambiar_estado(persona, "trasladada", "laura")
    end

    test "rechaza usuario vacío" do
      persona = Fabrica.persona()
      assert {:error, :usuario_vacio} = Persona.cambiar_estado(persona, :trasladada, "  ")
      assert {:error, :usuario_vacio} = Persona.cambiar_estado(persona, :trasladada, nil)
    end

    test "rechaza algo que no es una persona" do
      assert {:error, :persona_invalida} = Persona.cambiar_estado(%{}, :trasladada, "laura")
      assert {:error, :persona_invalida} = Persona.cambiar_estado(nil, :trasladada, "laura")
    end

    test "no modifica la persona original" do
      {:ok, persona} = crear_valida(estado: :reportada)
      {:ok, _cambiada} = Persona.cambiar_estado(persona, :localizada, "laura")

      assert persona.estado == :reportada
      assert length(persona.historial) == 1
    end

    test "acumula el historial con el cambio más reciente primero" do
      {:ok, persona} = crear_valida(estado: :sin_informacion, usuario: "laura")

      {:ok, persona} = Persona.cambiar_estado(persona, :reportada, "laura")
      {:ok, persona} = Persona.cambiar_estado(persona, :localizada, "pedro")
      {:error, :transicion_invalida} = Persona.cambiar_estado(persona, :reportada, "pedro")
      {:ok, persona} = Persona.cambiar_estado(persona, :en_albergue, "laura")

      assert persona.estado == :en_albergue

      assert resumen_historial(persona) == [
               {:localizada, :en_albergue, "laura"},
               {:reportada, :localizada, "pedro"},
               {:sin_informacion, :reportada, "laura"},
               {nil, :sin_informacion, "laura"}
             ]
    end
  end

  describe "coincide?/2" do
    setup do
      %{
        persona:
          Fabrica.persona(
            documento: "1094",
            nombre: "Andrés Pérez",
            zona: "centro",
            estado: :localizada
          )
      }
    end

    test "por nombre: contiene, sin distinguir mayúsculas", %{persona: persona} do
      assert Persona.coincide?(persona, nombre: "andrés")
      assert Persona.coincide?(persona, nombre: "PÉREZ")
      assert Persona.coincide?(persona, nombre: "drés pé")
      refute Persona.coincide?(persona, nombre: "maría")
    end

    test "por documento: igual exacto", %{persona: persona} do
      assert Persona.coincide?(persona, documento: "1094")
      refute Persona.coincide?(persona, documento: "109")
      refute Persona.coincide?(persona, documento: "10945")
    end

    test "por zona", %{persona: persona} do
      assert Persona.coincide?(persona, zona: "centro")
      refute Persona.coincide?(persona, zona: "norte")
    end

    test "por estado", %{persona: persona} do
      assert Persona.coincide?(persona, estado: :localizada)
      refute Persona.coincide?(persona, estado: :reportada)
    end

    test "combinados: deben cumplirse todos", %{persona: persona} do
      assert Persona.coincide?(persona,
               nombre: "andr",
               documento: "1094",
               zona: "centro",
               estado: :localizada
             )

      refute Persona.coincide?(persona, nombre: "andr", zona: "norte")
      refute Persona.coincide?(persona, nombre: "andr", estado: :reunificada)
      refute Persona.coincide?(persona, documento: "1094", nombre: "maría")
    end

    test "sin filtros coincide con cualquier persona", %{persona: persona} do
      assert Persona.coincide?(persona, [])
    end

    test "un filtro con valor nil se ignora", %{persona: persona} do
      assert Persona.coincide?(persona, nombre: nil, zona: "centro")
    end

    test "un filtro desconocido o mal formado no coincide", %{persona: persona} do
      refute Persona.coincide?(persona, edad: 30)
      refute Persona.coincide?(persona, nombre: 123)
      refute Persona.coincide?(persona, :no_es_lista)
      refute Persona.coincide?(%{}, nombre: "andr")
    end
  end

  describe "CSV de personas" do
    test "nombre del archivo y cabecera" do
      assert Persona.archivo_csv() == "personas.csv"
      assert Persona.cabecera_csv() == "documento;nombre;edad;zona;estado"
    end

    test "convierte a línea y de vuelta a persona (sin historial)" do
      {:ok, persona} = crear_valida()
      linea = Persona.to_linea(persona)

      assert linea == "1094;Andrés;30;centro;localizada"
      assert {:ok, leida} = Persona.de_linea(linea)
      assert leida == %{persona | historial: []}
    end

    test "sanitiza los textos al escribir la línea" do
      persona = Fabrica.persona(nombre: "Ana;María\nPérez")
      assert Persona.to_linea(persona) == "1094;Ana María Pérez;30;centro;localizada"
    end

    test "rechaza líneas corruptas" do
      assert {:error, :linea_invalida} = Persona.de_linea("1094;Andrés;30;centro")

      assert {:error, :linea_invalida} =
               Persona.de_linea("1094;Andrés;30;centro;localizada;extra")

      assert {:error, :linea_invalida} = Persona.de_linea(nil)
      assert {:error, :documento_vacio} = Persona.de_linea(";Andrés;30;centro;localizada")
      assert {:error, :nombre_vacio} = Persona.de_linea("1094;;30;centro;localizada")
      assert {:error, :edad_invalida} = Persona.de_linea("1094;Andrés;treinta;centro;localizada")
      assert {:error, :edad_invalida} = Persona.de_linea("1094;Andrés;200;centro;localizada")
      assert {:error, :zona_vacia} = Persona.de_linea("1094;Andrés;30;;localizada")
      assert {:error, :estado_invalido} = Persona.de_linea("1094;Andrés;30;centro;perdida")
    end
  end

  describe "CSV del historial" do
    setup do
      {:ok, persona} = crear_valida(estado: :reportada)
      {:ok, persona} = Persona.cambiar_estado(persona, :localizada, "pedro")
      %{persona: persona}
    end

    test "nombre del archivo y cabecera" do
      assert Persona.archivo_historial_csv() == "historial_personas.csv"
      assert Persona.cabecera_historial_csv() == "documento;fecha;de;a;usuario"
    end

    test "filas en orden cronológico, una por cambio", %{persona: persona} do
      assert [{"1094", %{de: nil, a: :reportada}}, {"1094", %{de: :reportada, a: :localizada}}] =
               Persona.filas_historial(persona)
    end

    test "convierte a línea y de vuelta; de vacío se lee como nil", %{persona: persona} do
      [inicial, cambio] = Persona.filas_historial(persona)

      linea_inicial = Persona.historial_a_linea(inicial)
      {"1094", %{fecha: fecha}} = inicial
      assert linea_inicial == "1094;#{fecha};;reportada;laura"

      assert {:ok, ^inicial} = Persona.historial_de_linea(linea_inicial)
      assert {:ok, ^cambio} = Persona.historial_de_linea(Persona.historial_a_linea(cambio))
    end

    test "rechaza líneas de historial corruptas" do
      fecha = "2026-01-01T00:00:00Z"

      assert {:error, :linea_invalida} = Persona.historial_de_linea("1094;#{fecha};;reportada")
      assert {:error, :linea_invalida} = Persona.historial_de_linea(nil)
      assert {:error, :documento_vacio} = Persona.historial_de_linea(";#{fecha};;reportada;laura")
      assert {:error, :fecha_vacia} = Persona.historial_de_linea("1094;;;reportada;laura")

      assert {:error, :estado_invalido} =
               Persona.historial_de_linea("1094;#{fecha};perdida;reportada;laura")

      assert {:error, :estado_invalido} = Persona.historial_de_linea("1094;#{fecha};;;laura")
      assert {:error, :usuario_vacio} = Persona.historial_de_linea("1094;#{fecha};;reportada;")
    end

    test "con_historial reconstruye el historial propio, el más reciente primero",
         %{persona: persona} do
      otra = Fabrica.persona(documento: "2020", estado: :reportada)
      {:ok, otra} = Persona.cambiar_estado(otra, :trasladada, "laura")

      filas = Persona.filas_historial(persona) ++ Persona.filas_historial(otra)
      sin_historial = %{persona | historial: []}

      assert Persona.con_historial(sin_historial, filas) == persona
    end

    @tag :tmp_dir
    test "ida y vuelta por archivo con Emergencias.CSV", %{persona: persona, tmp_dir: dir} do
      ruta_personas = Path.join(dir, Persona.archivo_csv())
      ruta_historial = Path.join(dir, Persona.archivo_historial_csv())

      :ok = CSV.escribir(ruta_personas, Persona.cabecera_csv(), [persona], &Persona.to_linea/1)

      [inicial, cambio] = Persona.filas_historial(persona)
      historial_csv = Persona.cabecera_historial_csv()
      :ok = CSV.escribir(ruta_historial, historial_csv, [inicial], &Persona.historial_a_linea/1)
      :ok = CSV.agregar(ruta_historial, historial_csv, cambio, &Persona.historial_a_linea/1)

      assert {:ok, [leida]} = CSV.leer(ruta_personas, &Persona.de_linea/1)
      assert {:ok, filas} = CSV.leer(ruta_historial, &Persona.historial_de_linea/1)
      assert Persona.con_historial(leida, filas) == persona
    end
  end
end
