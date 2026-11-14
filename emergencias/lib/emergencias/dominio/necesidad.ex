defmodule Emergencias.Dominio.Necesidad do
  @moduledoc """
  Entidad `Necesidad`: algo que una zona, un albergue o una persona requiere
  tras el terremoto (agua, alimentos, medicamentos...).

  Es una struct inmutable: cada función recibe una necesidad y devuelve una
  nueva. Ninguna función lanza excepciones; las operaciones que pueden fallar
  devuelven `{:ok, valor}` o `{:error, razon}`.

  ## Estados y transiciones

      pendiente   -> asignada, cancelada
      asignada    -> en_atencion, cancelada
      en_atencion -> atendida, cancelada
      atendida    -> (nada)
      cancelada   -> (nada)

  `:atendida` y `:cancelada` son estados cerrados.
  """

  alias Emergencias.{CSV, Util}

  @tipos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]
  @prioridades [:critica, :alta, :media, :baja]
  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]
  @cerrados [:atendida, :cancelada]
  @asociaciones [:zona, :albergue, :persona]

  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  @archivo "necesidades.csv"

  @cabecera "id;tipo;tipo_otro;descripcion;cantidad_requerida;cantidad_asignada;" <>
              "zona;prioridad;responsable;estado;asociada_a;fecha"

  defstruct id: nil,
            tipo: nil,
            tipo_otro: nil,
            descripcion: nil,
            cantidad_requerida: nil,
            cantidad_asignada: 0,
            zona: nil,
            prioridad: nil,
            responsable: nil,
            estado: :pendiente,
            asociada_a: nil,
            fecha: nil

  @type asociada_a :: {:zona, String.t()} | {:albergue, String.t()} | {:persona, String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: atom(),
          tipo_otro: String.t() | nil,
          descripcion: String.t(),
          cantidad_requerida: pos_integer(),
          cantidad_asignada: non_neg_integer(),
          zona: String.t(),
          prioridad: :critica | :alta | :media | :baja,
          responsable: String.t(),
          estado: :pendiente | :asignada | :en_atencion | :atendida | :cancelada,
          asociada_a: asociada_a(),
          fecha: String.t()
        }

  # ---------------------------------------------------------------------------
  # Creación
  # ---------------------------------------------------------------------------

  @doc """
  Crea una necesidad en estado `:pendiente`, con `cantidad_asignada` en 0 y la
  fecha actual.

  Por defecto queda asociada a su propia zona (`{:zona, zona}`). Para asociarla
  a un albergue o a una persona se pasa `asociada_a: {:albergue, "A01"}` o
  `asociada_a: {:persona, "123"}` en `opciones`.

  Errores posibles: `:id_invalido`, `:tipo_invalido`, `:prioridad_invalida`,
  `:cantidad_invalida` (debe ser un entero mayor que 0), `:descripcion_vacia`,
  `:tipo_otro_requerido` (cuando `tipo` es `:otra`), `:zona_invalida`,
  `:responsable_invalido` y `:asociada_a_invalida`.

  `descripcion` y `tipo_otro` se sanitizan (sin `;` ni saltos de línea). Si
  `tipo` no es `:otra`, `tipo_otro` se guarda como `nil`.
  """
  @spec crear(
          String.t(),
          atom(),
          String.t() | nil,
          String.t(),
          integer(),
          String.t(),
          atom(),
          String.t(),
          keyword()
        ) :: {:ok, t()} | {:error, atom()}
  def crear(
        id,
        tipo,
        tipo_otro,
        descripcion,
        cantidad_requerida,
        zona,
        prioridad,
        responsable,
        opciones \\ []
      )
      when is_list(opciones) do
    asociada_a = Keyword.get(opciones, :asociada_a, {:zona, zona})

    with {:ok, {descripcion, tipo_otro}} <-
           validar(
             id,
             tipo,
             tipo_otro,
             descripcion,
             cantidad_requerida,
             zona,
             prioridad,
             responsable,
             asociada_a
           ) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         tipo_otro: tipo_otro,
         descripcion: descripcion,
         cantidad_requerida: cantidad_requerida,
         cantidad_asignada: 0,
         zona: zona,
         prioridad: prioridad,
         responsable: responsable,
         estado: :pendiente,
         asociada_a: asociada_a,
         fecha: Util.ahora()
       }}
    end
  end

  # Devuelve {:ok, {descripcion_sanitizada, tipo_otro_normalizado}} o {:error, razon}.
  defp validar(
         id,
         tipo,
         tipo_otro,
         descripcion,
         cantidad,
         zona,
         prioridad,
         responsable,
         asociada_a
       ) do
    descripcion = Util.sanitizar_texto(descripcion)

    with :ok <- validar_identificador(id, :id_invalido),
         :ok <- validar_en(tipo, @tipos, :tipo_invalido),
         :ok <- validar_en(prioridad, @prioridades, :prioridad_invalida),
         :ok <- validar_cantidad(cantidad),
         :ok <- validar_descripcion(descripcion),
         {:ok, tipo_otro} <- normalizar_tipo_otro(tipo, tipo_otro),
         :ok <- validar_identificador(zona, :zona_invalida),
         :ok <- validar_identificador(responsable, :responsable_invalido),
         :ok <- validar_asociada_a(asociada_a) do
      {:ok, {descripcion, tipo_otro}}
    end
  end

  defp validar_en(valor, permitidos, error) do
    if valor in permitidos, do: :ok, else: {:error, error}
  end

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_otro), do: {:error, :cantidad_invalida}

  defp validar_descripcion(descripcion) do
    if Util.vacio?(descripcion), do: {:error, :descripcion_vacia}, else: :ok
  end

  defp normalizar_tipo_otro(:otra, texto) do
    texto = Util.sanitizar_texto(texto)
    if Util.vacio?(texto), do: {:error, :tipo_otro_requerido}, else: {:ok, texto}
  end

  defp normalizar_tipo_otro(_tipo, _texto), do: {:ok, nil}

  # Un identificador es un texto no vacío que ya está "limpio" para CSV
  # (sin `;`, sin saltos de línea y sin espacios en los extremos).
  defp validar_identificador(valor, error) do
    if is_binary(valor) and not Util.vacio?(valor) and Util.sanitizar_texto(valor) == valor,
      do: :ok,
      else: {:error, error}
  end

  defp validar_asociada_a({tipo, codigo}) when tipo in @asociaciones,
    do: validar_identificador(codigo, :asociada_a_invalida)

  defp validar_asociada_a(_otro), do: {:error, :asociada_a_invalida}

  # ---------------------------------------------------------------------------
  # Estado
  # ---------------------------------------------------------------------------

  @doc """
  Cambia el estado según la tabla de transiciones del módulo.

    * Necesidad cerrada (`:atendida` o `:cancelada`): `{:error, :ya_cerrada}`.
    * Transición que no existe en la tabla: `{:error, :transicion_invalida}`.
  """
  @spec cambiar_estado(t(), atom()) :: {:ok, t()} | {:error, :ya_cerrada | :transicion_invalida}
  def cambiar_estado(%__MODULE__{estado: estado}, _nuevo) when estado in @cerrados,
    do: {:error, :ya_cerrada}

  def cambiar_estado(%__MODULE__{estado: estado} = necesidad, nuevo) do
    if nuevo in Map.get(@transiciones, estado, []) do
      {:ok, %__MODULE__{necesidad | estado: nuevo}}
    else
      {:error, :transicion_invalida}
    end
  end

  # ---------------------------------------------------------------------------
  # Cantidades
  # ---------------------------------------------------------------------------

  @doc """
  Cantidad que aún falta por asignar (requerida menos asignada).
  """
  @spec cantidad_faltante(t()) :: non_neg_integer()
  def cantidad_faltante(%__MODULE__{} = necesidad),
    do: necesidad.cantidad_requerida - necesidad.cantidad_asignada

  @doc """
  Suma `cantidad` a `cantidad_asignada`.

    * Necesidad cerrada: `{:error, :ya_cerrada}`.
    * `cantidad` que no es un entero mayor que 0: `{:error, :cantidad_invalida}`.
    * `cantidad` mayor que lo que falta: `{:error, :excede_requerido}`.

  Si la necesidad estaba `:pendiente` y con esta asignación queda totalmente
  cubierta, pasa a `:asignada`; si la cobertura es parcial sigue `:pendiente`.
  En cualquier otro estado, el estado no cambia.
  """
  @spec registrar_asignacion(t(), integer()) ::
          {:ok, t()} | {:error, :ya_cerrada | :cantidad_invalida | :excede_requerido}
  def registrar_asignacion(%__MODULE__{estado: estado}, _cantidad) when estado in @cerrados,
    do: {:error, :ya_cerrada}

  def registrar_asignacion(%__MODULE__{} = necesidad, cantidad)
      when is_integer(cantidad) and cantidad > 0 do
    if cantidad > cantidad_faltante(necesidad) do
      {:error, :excede_requerido}
    else
      asignada = necesidad.cantidad_asignada + cantidad

      estado =
        if necesidad.estado == :pendiente and asignada == necesidad.cantidad_requerida,
          do: :asignada,
          else: necesidad.estado

      {:ok, %__MODULE__{necesidad | cantidad_asignada: asignada, estado: estado}}
    end
  end

  def registrar_asignacion(%__MODULE__{}, _cantidad), do: {:error, :cantidad_invalida}

  # ---------------------------------------------------------------------------
  # Prioridad
  # ---------------------------------------------------------------------------

  @doc """
  Peso numérico de una prioridad, para ordenar: `:critica` 4, `:alta` 3,
  `:media` 2, `:baja` 1.
  """
  @spec peso_prioridad(:critica | :alta | :media | :baja) :: 1..4
  def peso_prioridad(:critica), do: 4
  def peso_prioridad(:alta), do: 3
  def peso_prioridad(:media), do: 2
  def peso_prioridad(:baja), do: 1

  # ---------------------------------------------------------------------------
  # CSV (necesidades.csv)
  # ---------------------------------------------------------------------------

  @doc "Nombre del archivo CSV de necesidades."
  @spec archivo() :: String.t()
  def archivo, do: @archivo

  @doc "Línea de cabecera del archivo CSV."
  @spec cabecera() :: String.t()
  def cabecera, do: @cabecera

  @doc """
  Convierte la necesidad en una línea CSV (sin salto de línea). `asociada_a`
  se escribe como `zona:centro`, `albergue:A01` o `persona:123`.
  """
  @spec to_linea(t()) :: String.t()
  def to_linea(%__MODULE__{} = necesidad) do
    CSV.unir([
      necesidad.id,
      necesidad.tipo,
      Util.sanitizar_texto(necesidad.tipo_otro),
      Util.sanitizar_texto(necesidad.descripcion),
      necesidad.cantidad_requerida,
      necesidad.cantidad_asignada,
      necesidad.zona,
      necesidad.prioridad,
      necesidad.responsable,
      necesidad.estado,
      asociada_a_a_texto(necesidad.asociada_a),
      necesidad.fecha
    ])
  end

  @doc """
  Convierte una línea CSV en una necesidad, aplicando las mismas validaciones
  que `crear/9`. Ante una línea corrupta devuelve `{:error, razon}`.
  """
  @spec de_linea(term()) :: {:ok, t()} | {:error, atom()}
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [
        id,
        tipo,
        tipo_otro,
        descripcion,
        requerida,
        asignada,
        zona,
        prioridad,
        resp,
        estado,
        asoc,
        fecha
      ] ->
        construir_desde_campos(%{
          id: id,
          tipo: tipo,
          tipo_otro: tipo_otro,
          descripcion: descripcion,
          requerida: requerida,
          asignada: asignada,
          zona: zona,
          prioridad: prioridad,
          responsable: resp,
          estado: estado,
          asociada_a: asoc,
          fecha: fecha
        })

      _otro ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}

  defp construir_desde_campos(campos) do
    with {:ok, tipo} <- Util.parsear_enum(campos.tipo, @tipos),
         {:ok, prioridad} <- Util.parsear_enum(campos.prioridad, @prioridades),
         {:ok, estado} <- Util.parsear_enum(campos.estado, @estados),
         {:ok, requerida} <- Util.parsear_entero(campos.requerida),
         {:ok, asignada} <- Util.parsear_entero_no_negativo(campos.asignada),
         :ok <- validar_asignada(asignada, requerida),
         {:ok, asociada_a} <- texto_a_asociada_a(campos.asociada_a),
         :ok <- validar_fecha(campos.fecha),
         {:ok, {descripcion, tipo_otro}} <-
           validar(
             campos.id,
             tipo,
             campos.tipo_otro,
             campos.descripcion,
             requerida,
             campos.zona,
             prioridad,
             campos.responsable,
             asociada_a
           ) do
      {:ok,
       %__MODULE__{
         id: campos.id,
         tipo: tipo,
         tipo_otro: tipo_otro,
         descripcion: descripcion,
         cantidad_requerida: requerida,
         cantidad_asignada: asignada,
         zona: campos.zona,
         prioridad: prioridad,
         responsable: campos.responsable,
         estado: estado,
         asociada_a: asociada_a,
         fecha: campos.fecha
       }}
    end
  end

  defp validar_asignada(asignada, requerida) when asignada <= requerida, do: :ok
  defp validar_asignada(_asignada, _requerida), do: {:error, :cantidad_invalida}

  defp validar_fecha(fecha) do
    if Util.vacio?(fecha), do: {:error, :fecha_invalida}, else: :ok
  end

  defp asociada_a_a_texto({tipo, codigo}), do: "#{tipo}:#{codigo}"
  defp asociada_a_a_texto(_otro), do: ""

  defp texto_a_asociada_a(texto) do
    case String.split(texto, ":", parts: 2) do
      ["zona", codigo] -> {:ok, {:zona, codigo}}
      ["albergue", codigo] -> {:ok, {:albergue, codigo}}
      ["persona", codigo] -> {:ok, {:persona, codigo}}
      _otro -> {:error, :asociada_a_invalida}
    end
  end
end
