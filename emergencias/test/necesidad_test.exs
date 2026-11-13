defmodule Emergencias.Dominio.NecesidadTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Fabrica

  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]
  @cerrados [:atendida, :cancelada]

  @transiciones_validas [
    {:pendiente, :asignada},
    {:pendiente, :cancelada},
    {:asignada, :en_atencion},
    {:asignada, :cancelada},
    {:en_atencion, :atendida},
    {:en_atencion, :cancelada}
  ]

  # Todas las parejas (estado abierto, nuevo) que NO están en la tabla.
  @transiciones_invalidas for desde <- [:pendiente, :asignada, :en_atencion],
                              hacia <- @estados,
                              {desde, hacia} not in @transiciones_validas,
                              do: {desde, hacia}

  # Argumentos válidos de crear/8, para variar uno solo en cada prueba.
  defp crear(cambios \\ [], opciones \\ []) do
    base = [
      id: "N001",
      tipo: :agua,
      tipo_otro: nil,
      descripcion: "Agua para el sector 3",
      cantidad_requerida: 30,
      zona: "centro",
      prioridad: :critica,
      responsable: "laura"
    ]

    a = Keyword.merge(base, cambios)

    Necesidad.crear(
      a[:id],
      a[:tipo],
      a[:tipo_otro],
      a[:descripcion],
      a[:cantidad_requerida],
      a[:zona],
      a[:prioridad],
      a[:responsable],
      opciones
    )
  end

  describe "crear/8" do
    test "crea una necesidad válida con los valores por defecto" do
      assert {:ok, %Necesidad{} = n} = crear()
      assert n.id == "N001"
      assert n.tipo == :agua
      assert n.tipo_otro == nil
      assert n.descripcion == "Agua para el sector 3"
      assert n.cantidad_requerida == 30
      assert n.cantidad_asignada == 0
      assert n.zona == "centro"
      assert n.prioridad == :critica
      assert n.responsable == "laura"
      assert n.estado == :pendiente
      assert n.asociada_a == {:zona, "centro"}
      assert {:ok, _fecha, _offset} = DateTime.from_iso8601(n.fecha)
    end

    test "acepta todos los tipos y prioridades válidos" do
      for tipo <- [
            :agua,
            :alimentos,
            :medicamentos,
            :primeros_auxilios,
            :refugio,
            :transporte,
            :rescate
          ] do
        assert {:ok, %Necesidad{tipo: ^tipo}} = crear(tipo: tipo)
      end

      for prioridad <- [:critica, :alta, :media, :baja] do
        assert {:ok, %Necesidad{prioridad: ^prioridad}} = crear(prioridad: prioridad)
      end
    end

    test "tipo :otra con tipo_otro es válido" do
      assert {:ok, n} = crear(tipo: :otra, tipo_otro: "Linternas")
      assert n.tipo == :otra
      assert n.tipo_otro == "Linternas"
    end

    test "si el tipo no es :otra, tipo_otro se guarda como nil" do
      assert {:ok, n} = crear(tipo: :agua, tipo_otro: "ignorado")
      assert n.tipo_otro == nil
    end

    test "puede asociarse a un albergue o a una persona" do
      assert {:ok, a} = crear([], asociada_a: {:albergue, "A01"})
      assert a.asociada_a == {:albergue, "A01"}

      assert {:ok, p} = crear([], asociada_a: {:persona, "123"})
      assert p.asociada_a == {:persona, "123"}
    end

    test "sanitiza la descripción (sin punto y coma ni saltos de línea)" do
      assert {:ok, n} = crear(descripcion: "  Agua; urgente\nya ")
      assert n.descripcion == "Agua  urgente ya"
    end

    test "rechaza cantidad 0" do
      assert {:error, :cantidad_invalida} = crear(cantidad_requerida: 0)
    end

    test "rechaza cantidad negativa" do
      assert {:error, :cantidad_invalida} = crear(cantidad_requerida: -5)
    end

    test "rechaza cantidad que no es entera" do
      assert {:error, :cantidad_invalida} = crear(cantidad_requerida: 2.5)
      assert {:error, :cantidad_invalida} = crear(cantidad_requerida: "10")
      assert {:error, :cantidad_invalida} = crear(cantidad_requerida: nil)
    end

    test "rechaza tipo inválido" do
      assert {:error, :tipo_invalido} = crear(tipo: :comida)
      assert {:error, :tipo_invalido} = crear(tipo: "agua")
      assert {:error, :tipo_invalido} = crear(tipo: nil)
    end

    test "rechaza prioridad inválida" do
      assert {:error, :prioridad_invalida} = crear(prioridad: :urgente)
      assert {:error, :prioridad_invalida} = crear(prioridad: "alta")
    end

    test "rechaza descripción vacía" do
      assert {:error, :descripcion_vacia} = crear(descripcion: "")
      assert {:error, :descripcion_vacia} = crear(descripcion: "   ")
      assert {:error, :descripcion_vacia} = crear(descripcion: ";")
      assert {:error, :descripcion_vacia} = crear(descripcion: nil)
    end

    test "tipo :otra exige tipo_otro" do
      assert {:error, :tipo_otro_requerido} = crear(tipo: :otra, tipo_otro: nil)
      assert {:error, :tipo_otro_requerido} = crear(tipo: :otra, tipo_otro: "")
      assert {:error, :tipo_otro_requerido} = crear(tipo: :otra, tipo_otro: "   ")
    end

    test "rechaza id, zona y responsable vacíos o con punto y coma" do
      assert {:error, :id_invalido} = crear(id: "")
      assert {:error, :id_invalido} = crear(id: "N0;01")
      assert {:error, :zona_invalida} = crear(zona: " ")
      assert {:error, :zona_invalida} = crear(zona: nil)
      assert {:error, :responsable_invalido} = crear(responsable: "")
      assert {:error, :responsable_invalido} = crear(responsable: "la;ura")
    end

    test "rechaza asociada_a inválida" do
      assert {:error, :asociada_a_invalida} = crear([], asociada_a: {:mascota, "M001"})
      assert {:error, :asociada_a_invalida} = crear([], asociada_a: {:zona, ""})
      assert {:error, :asociada_a_invalida} = crear([], asociada_a: "zona:centro")
      assert {:error, :asociada_a_invalida} = crear([], asociada_a: nil)
    end
  end

  describe "cambiar_estado/2 — transiciones válidas" do
    for {desde, hacia} <- @transiciones_validas do
      test "#{desde} -> #{hacia}" do
        necesidad = Fabrica.necesidad(estado: unquote(desde))
        assert {:ok, nueva} = Necesidad.cambiar_estado(necesidad, unquote(hacia))
        assert nueva.estado == unquote(hacia)
        assert %{nueva | estado: unquote(desde)} == necesidad
      end
    end
  end

  describe "cambiar_estado/2 — transiciones inválidas" do
    for {desde, hacia} <- @transiciones_invalidas do
      test "#{desde} -> #{hacia}" do
        necesidad = Fabrica.necesidad(estado: unquote(desde))

        assert {:error, :transicion_invalida} =
                 Necesidad.cambiar_estado(necesidad, unquote(hacia))
      end
    end

    test "un estado que no existe es transición inválida" do
      assert {:error, :transicion_invalida} =
               Necesidad.cambiar_estado(Fabrica.necesidad(), :volando)
    end
  end

  describe "cambiar_estado/2 — necesidad cerrada" do
    for cerrado <- @cerrados, nuevo <- @estados do
      test "#{cerrado} -> #{nuevo} devuelve :ya_cerrada" do
        necesidad = Fabrica.necesidad(estado: unquote(cerrado))
        assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(necesidad, unquote(nuevo))
      end
    end

    test "no se puede cerrar dos veces" do
      necesidad = Fabrica.necesidad(estado: :en_atencion)
      assert {:ok, atendida} = Necesidad.cambiar_estado(necesidad, :atendida)
      assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(atendida, :atendida)
      assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(atendida, :cancelada)
    end

    test "no se puede cancelar dos veces" do
      assert {:ok, cancelada} = Necesidad.cambiar_estado(Fabrica.necesidad(), :cancelada)
      assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(cancelada, :cancelada)
    end
  end

  describe "cantidad_faltante/1" do
    test "es la requerida menos la asignada" do
      assert Necesidad.cantidad_faltante(Fabrica.necesidad(cantidad_requerida: 30)) == 30

      assert Necesidad.cantidad_faltante(
               Fabrica.necesidad(cantidad_requerida: 30, cantidad_asignada: 12)
             ) == 18

      assert Necesidad.cantidad_faltante(
               Fabrica.necesidad(cantidad_requerida: 30, cantidad_asignada: 30)
             ) == 0
    end
  end

  describe "registrar_asignacion/2" do
    test "asignación parcial suma y mantiene :pendiente" do
      necesidad = Fabrica.necesidad(cantidad_requerida: 30)
      assert {:ok, n} = Necesidad.registrar_asignacion(necesidad, 10)
      assert n.cantidad_asignada == 10
      assert n.estado == :pendiente
      assert Necesidad.cantidad_faltante(n) == 20
    end

    test "asignación total pasa a :asignada" do
      necesidad = Fabrica.necesidad(cantidad_requerida: 30)
      assert {:ok, n} = Necesidad.registrar_asignacion(necesidad, 30)
      assert n.cantidad_asignada == 30
      assert n.estado == :asignada
      assert Necesidad.cantidad_faltante(n) == 0
    end

    test "dos asignaciones parciales que completan pasan a :asignada" do
      necesidad = Fabrica.necesidad(cantidad_requerida: 30)
      assert {:ok, parcial} = Necesidad.registrar_asignacion(necesidad, 10)
      assert parcial.estado == :pendiente
      assert {:ok, total} = Necesidad.registrar_asignacion(parcial, 20)
      assert total.cantidad_asignada == 30
      assert total.estado == :asignada
    end

    test "rechaza una cantidad que supera lo que falta" do
      necesidad = Fabrica.necesidad(cantidad_requerida: 30, cantidad_asignada: 25)
      assert {:error, :excede_requerido} = Necesidad.registrar_asignacion(necesidad, 6)
    end

    test "rechaza asignar de más sobre una necesidad ya cubierta" do
      necesidad =
        Fabrica.necesidad(cantidad_requerida: 30, cantidad_asignada: 30, estado: :asignada)

      assert {:error, :excede_requerido} = Necesidad.registrar_asignacion(necesidad, 1)
    end

    test "rechaza cantidad que no es un entero positivo" do
      necesidad = Fabrica.necesidad()
      assert {:error, :cantidad_invalida} = Necesidad.registrar_asignacion(necesidad, 0)
      assert {:error, :cantidad_invalida} = Necesidad.registrar_asignacion(necesidad, -3)
      assert {:error, :cantidad_invalida} = Necesidad.registrar_asignacion(necesidad, 2.0)
      assert {:error, :cantidad_invalida} = Necesidad.registrar_asignacion(necesidad, "5")
    end

    test "una necesidad atendida no vuelve a consumir recursos" do
      necesidad = Fabrica.necesidad(estado: :atendida, cantidad_asignada: 10)
      assert {:error, :ya_cerrada} = Necesidad.registrar_asignacion(necesidad, 5)
    end

    test "una necesidad cancelada no consume recursos" do
      necesidad = Fabrica.necesidad(estado: :cancelada)
      assert {:error, :ya_cerrada} = Necesidad.registrar_asignacion(necesidad, 5)
    end

    test "una necesidad cerrada devuelve :ya_cerrada aunque la cantidad sea inválida" do
      necesidad = Fabrica.necesidad(estado: :atendida)
      assert {:error, :ya_cerrada} = Necesidad.registrar_asignacion(necesidad, 0)
      assert {:error, :ya_cerrada} = Necesidad.registrar_asignacion(necesidad, 9_999)
    end

    test "en estados abiertos distintos de :pendiente, el estado no cambia" do
      necesidad =
        Fabrica.necesidad(estado: :en_atencion, cantidad_requerida: 30, cantidad_asignada: 20)

      assert {:ok, n} = Necesidad.registrar_asignacion(necesidad, 10)
      assert n.cantidad_asignada == 30
      assert n.estado == :en_atencion
    end
  end

  describe "peso_prioridad/1" do
    test "crítica 4, alta 3, media 2, baja 1" do
      assert Necesidad.peso_prioridad(:critica) == 4
      assert Necesidad.peso_prioridad(:alta) == 3
      assert Necesidad.peso_prioridad(:media) == 2
      assert Necesidad.peso_prioridad(:baja) == 1
    end
  end

  describe "CSV" do
    test "archivo y cabecera" do
      assert Necesidad.archivo() == "necesidades.csv"

      assert Necesidad.cabecera() ==
               "id;tipo;tipo_otro;descripcion;cantidad_requerida;cantidad_asignada;" <>
                 "zona;prioridad;responsable;estado;asociada_a;fecha"
    end

    test "a_linea escribe todos los campos separados por ;" do
      assert Necesidad.a_linea(Fabrica.necesidad()) ==
               "N001;agua;;Punto de atención sector 3;30;0;centro;critica;laura;pendiente;" <>
                 "zona:centro;2026-01-01T00:00:00Z"
    end

    test "a_linea escribe asociada_a como albergue:A01 y persona:123" do
      assert Necesidad.a_linea(Fabrica.necesidad(asociada_a: {:albergue, "A01"})) =~
               ";albergue:A01;"

      assert Necesidad.a_linea(Fabrica.necesidad(asociada_a: {:persona, "123"})) =~
               ";persona:123;"
    end

    test "a_linea sanitiza el texto libre" do
      linea = Necesidad.a_linea(Fabrica.necesidad(descripcion: "uno; dos\ntres"))
      assert length(String.split(linea, ";")) == 12
      assert linea =~ ";uno  dos tres;"
    end

    test "de_linea(a_linea(n)) devuelve la misma necesidad" do
      necesidades = [
        Fabrica.necesidad(),
        Fabrica.necesidad(
          asociada_a: {:albergue, "A01"},
          estado: :asignada,
          cantidad_asignada: 30
        ),
        Fabrica.necesidad(asociada_a: {:persona, "123"}, prioridad: :baja, estado: :cancelada),
        Fabrica.necesidad(tipo: :otra, tipo_otro: "Linternas", cantidad_asignada: 5)
      ]

      for n <- necesidades do
        assert {:ok, ^n} = n |> Necesidad.a_linea() |> Necesidad.de_linea()
      end
    end

    test "de_linea rechaza una línea con otro número de campos" do
      assert {:error, :linea_invalida} = Necesidad.de_linea("N001;agua;;desc;30")
      assert {:error, :linea_invalida} = Necesidad.de_linea("")
    end

    test "de_linea rechaza algo que no es texto" do
      assert {:error, :linea_invalida} = Necesidad.de_linea(nil)
    end

    test "de_linea rechaza valores corruptos en cada campo" do
      base = Necesidad.a_linea(Fabrica.necesidad())

      casos = [
        {"agua", "comida"},
        {"critica", "urgente"},
        {"pendiente", "volando"},
        {";30;0;", ";3x;0;"},
        {";30;0;", ";30;-1;"},
        {";30;0;", ";30;31;"},
        {";30;0;", ";0;0;"},
        {"zona:centro", "mascota:M001"},
        {"zona:centro", "centro"},
        {"zona:centro", "zona:"},
        {"2026-01-01T00:00:00Z", ""},
        {"Punto de atención sector 3", ""}
      ]

      for {original, corrupto} <- casos do
        linea = String.replace(base, original, corrupto)
        assert {:error, _razon} = Necesidad.de_linea(linea), "debía fallar: #{linea}"
      end
    end

    test "de_linea rechaza tipo :otra sin tipo_otro" do
      linea =
        "N001;otra;;Linternas;10;0;centro;alta;laura;pendiente;zona:centro;2026-01-01T00:00:00Z"

      assert {:error, :tipo_otro_requerido} = Necesidad.de_linea(linea)
    end
  end
end
