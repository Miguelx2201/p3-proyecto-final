defmodule Emergencias.Fabrica do
  @moduledoc """
  Construye entidades válidas para las pruebas. Solo se compila con `MIX_ENV=test`.

  Cada función recibe una keyword list (o un mapa) para sobrescribir campos:

      Fabrica.necesidad(prioridad: :baja, cantidad_requerida: 5)

  Usa `struct!/2`, así que un nombre de campo que no exista en la entidad falla
  de inmediato en vez de ignorarse. Los valores por defecto siguen los campos de
  cada entidad definidos en su issue; si una entidad cambia sus campos, se
  actualiza aquí.
  """

  alias Emergencias.Dominio.{
    Actividad,
    Albergue,
    Mascota,
    Movimiento,
    Mensaje,
    Necesidad,
    Persona,
    PuntoAtencion,
    Recurso,
    Sector,
    Usuario,
    Zona
  }

  @contrasena "1234"
  @fecha "2026-01-01T00:00:00Z"

  @doc """
  Construye una struct de `modulo` mezclando `valores_por_defecto` con `atributos`.
  Los `atributos` ganan sobre los valores por defecto.
  """
  def construir(modulo, valores_por_defecto, atributos \\ []) do
    campos = valores_por_defecto |> Map.new() |> Map.merge(Map.new(atributos))
    struct!(modulo, campos)
  end

  @doc "Contraseña en texto plano del usuario de la fábrica."
  def contrasena, do: @contrasena

  def usuario(atributos \\ []) do
    construir(
      Usuario,
      [
        username: "laura",
        password_hash: Base.encode16(:crypto.hash(:sha256, @contrasena)),
        nombre_completo: "Laura Gómez",
        tipo: :coordinador,
        zona: "centro",
        conectado: false
      ],
      atributos
    )
  end

  def zona(atributos \\ []) do
    construir(
      Zona,
      [
        codigo: "centro",
        nombre: "Zona Centro",
        nivel: :critico,
        personas_afectadas: 0,
        sectores: []
      ],
      atributos
    )
  end

  def sector(atributos \\ []) do
    construir(
      Sector,
      [codigo: "S1", nombre: "Sector 1", personas_afectadas: 0, puntos_atencion: []],
      atributos
    )
  end

  def punto_atencion(atributos \\ []) do
    construir(
      PuntoAtencion,
      [codigo: "P1", nombre: "Punto 1", personas_afectadas: 0],
      atributos
    )
  end

  def necesidad(atributos \\ []) do
    construir(
      Necesidad,
      [
        id: "N001",
        tipo: :agua,
        tipo_otro: nil,
        descripcion: "Punto de atención sector 3",
        cantidad_requerida: 30,
        cantidad_asignada: 0,
        zona: "centro",
        prioridad: :critica,
        responsable: "laura",
        estado: :pendiente,
        asociada_a: {:zona, "centro"},
        fecha: @fecha
      ],
      atributos
    )
  end

  def recurso(atributos \\ []) do
    construir(
      Recurso,
      [
        id: "R001",
        nombre: "agua",
        categoria: :agua,
        cantidad_disponible: 50,
        unidad: "litros",
        ubicacion: "centro_acopio_1",
        zona: "centro"
      ],
      atributos
    )
  end

  def movimiento(atributos \\ []) do
    construir(
      Movimiento,
      [
        id: "MV001",
        recurso_id: "R001",
        tipo: :entrada,
        cantidad: 10,
        fecha: @fecha,
        usuario: "laura",
        referencia: nil
      ],
      atributos
    )
  end

  def actividad(atributos \\ []) do
    construir(
      Actividad,
      [
        fecha: @fecha,
        usuario: "laura",
        comando: "crear_necesidad",
        resultado: "ok"
      ],
      atributos
    )
  end

  def persona(atributos \\ []) do
    construir(
      Persona,
      [
        documento: "1094",
        nombre: "Andrés",
        edad: 30,
        zona: "centro",
        estado: :localizada,
        historial: []
      ],
      atributos
    )
  end

  def mascota(atributos \\ []) do
    construir(
      Mascota,
      [
        id: "M001",
        tipo: :perdida,
        especie: "perro",
        nombre: "Luna",
        caracteristicas: "",
        color: "negra",
        tamano: :mediano,
        zona: "centro",
        contacto: "3001234567",
        estado: :activa
      ],
      atributos
    )
  end

  def albergue(atributos \\ []) do
    construir(
      Albergue,
      [
        id: "A01",
        nombre: "Albergue Norte",
        zona: "centro",
        capacidad_maxima: 100,
        ocupacion_actual: 0,
        personas: MapSet.new()
      ],
      atributos
    )
  end

  def mensaje(atributos \\ []) do
    construir(
      Mensaje,
      [
        id: "MS001",
        fecha: @fecha,
        remitente: "laura",
        documento_destinatario: "1094",
        contenido: "Estamos bien, te esperamos en el albergue",
        estado: :pendiente
      ],
      atributos
    )
  end
end
