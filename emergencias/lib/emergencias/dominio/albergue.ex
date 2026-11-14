defmodule Emergencias.Dominio.Albergue do
  @moduledoc """
  Albergue temporal para personas afectadas.

  Guarda la capacidad, la ocupación y los documentos de las personas que
  ingresaron (`personas`, un `MapSet`). Las necesidades y los recursos del
  albergue no se guardan aquí: se asocian desde fuera con
  `asociada_a: {:albergue, id}` y con `ubicacion`.

  Todas las funciones son puras: reciben una struct y devuelven una nueva.
  Las operaciones que pueden fallar devuelven `{:ok, albergue}` o
  `{:error, razon}`; las consultas (`cupos_disponibles/1` y
  `porcentaje_ocupacion/1`) devuelven el valor directamente.

  Invariante: `0 <= ocupacion_actual <= capacidad_maxima`. La ocupación puede
  ser mayor que el número de documentos en `personas`, porque `crear/5` acepta
  una ocupación inicial de personas que no se registraron por documento.
  """

  alias Emergencias.Util

  defstruct id: nil,
            nombre: nil,
            zona: nil,
            capacidad_maxima: 0,
            ocupacion_actual: 0,
            personas: MapSet.new()

  @type t :: %__MODULE__{
          id: String.t(),
          nombre: String.t(),
          zona: String.t(),
          capacidad_maxima: non_neg_integer(),
          ocupacion_actual: non_neg_integer(),
          personas: MapSet.t(String.t())
        }

  # ---------------------------------------------------------------------------
  # Creación
  # ---------------------------------------------------------------------------

  @doc """
  Crea un albergue sin personas registradas.

  Errores posibles:

    * `:id_invalido`, `:nombre_invalido`, `:zona_invalida`: texto vacío o que
      no es texto.
    * `:capacidad_invalida`: la capacidad no es un entero mayor o igual a 0.
    * `:ocupacion_invalida`: la ocupación no es un entero mayor o igual a 0.
    * `:ocupacion_supera_capacidad`: la ocupación es mayor que la capacidad.
  """
  @spec crear(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def crear(id, nombre, zona, capacidad, ocupacion) do
    with {:ok, id} <- validar_texto(id, :id_invalido),
         {:ok, nombre} <- validar_texto(nombre, :nombre_invalido),
         {:ok, zona} <- validar_texto(zona, :zona_invalida),
         :ok <- validar_no_negativo(capacidad, :capacidad_invalida),
         :ok <- validar_no_negativo(ocupacion, :ocupacion_invalida),
         :ok <- validar_ocupacion(ocupacion, capacidad) do
      {:ok,
       %__MODULE__{
         id: id,
         nombre: nombre,
         zona: zona,
         capacidad_maxima: capacidad,
         ocupacion_actual: ocupacion,
         personas: MapSet.new()
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  @doc """
  Cupos libres: capacidad máxima menos ocupación actual.
  """
  @spec cupos_disponibles(t()) :: integer()
  def cupos_disponibles(%__MODULE__{capacidad_maxima: capacidad, ocupacion_actual: ocupacion}) do
    capacidad - ocupacion
  end

  @doc """
  Porcentaje de ocupación como decimal entre `0.0` y `100.0`, sin redondear.

  Si la capacidad es 0 devuelve `0.0` para no dividir por cero.
  """
  @spec porcentaje_ocupacion(t()) :: float()
  def porcentaje_ocupacion(%__MODULE__{capacidad_maxima: 0}), do: 0.0

  def porcentaje_ocupacion(%__MODULE__{capacidad_maxima: capacidad, ocupacion_actual: ocupacion}) do
    ocupacion * 100 / capacidad
  end

  # ---------------------------------------------------------------------------
  # Ingreso y salida de personas
  # ---------------------------------------------------------------------------

  @doc """
  Registra el ingreso de la persona con `documento`: suma 1 a la ocupación y
  agrega el documento a `personas`.

  Errores, en este orden de revisión:

    * `:documento_invalido`: documento vacío o que no es texto.
    * `:sin_cupo`: el albergue está lleno (incluye capacidad 0).
    * `:ya_registrado`: el documento ya está en el albergue.
  """
  @spec registrar_ingreso(t(), term()) :: {:ok, t()} | {:error, atom()}
  def registrar_ingreso(%__MODULE__{} = albergue, documento) do
    with {:ok, documento} <- validar_texto(documento, :documento_invalido),
         :ok <- verificar_cupo(albergue),
         :ok <- verificar_no_registrado(albergue, documento) do
      {:ok,
       %__MODULE__{
         albergue
         | ocupacion_actual: albergue.ocupacion_actual + 1,
           personas: MapSet.put(albergue.personas, documento)
       }}
    end
  end

  @doc """
  Registra la salida de la persona con `documento`: resta 1 a la ocupación y
  quita el documento de `personas`.

  Errores:

    * `:documento_invalido`: documento vacío o que no es texto.
    * `:persona_no_esta`: el documento no está en el albergue.
  """
  @spec registrar_salida(t(), term()) :: {:ok, t()} | {:error, atom()}
  def registrar_salida(%__MODULE__{} = albergue, documento) do
    with {:ok, documento} <- validar_texto(documento, :documento_invalido),
         :ok <- verificar_presente(albergue, documento) do
      {:ok,
       %__MODULE__{
         albergue
         | ocupacion_actual: albergue.ocupacion_actual - 1,
           personas: MapSet.delete(albergue.personas, documento)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Validaciones privadas
  # ---------------------------------------------------------------------------

  # Sanitiza primero (quita `;`, saltos de línea y espacios de los extremos) y
  # luego revisa que no haya quedado vacío.
  defp validar_texto(texto, error) when is_binary(texto) do
    case Util.sanitizar_texto(texto) do
      "" -> {:error, error}
      limpio -> {:ok, limpio}
    end
  end

  defp validar_texto(_otro, error), do: {:error, error}

  defp validar_no_negativo(numero, _error) when is_integer(numero) and numero >= 0, do: :ok
  defp validar_no_negativo(_otro, error), do: {:error, error}

  defp validar_ocupacion(ocupacion, capacidad) when ocupacion <= capacidad, do: :ok
  defp validar_ocupacion(_ocupacion, _capacidad), do: {:error, :ocupacion_supera_capacidad}

  defp verificar_cupo(albergue) do
    if cupos_disponibles(albergue) > 0, do: :ok, else: {:error, :sin_cupo}
  end

  defp verificar_no_registrado(albergue, documento) do
    if MapSet.member?(albergue.personas, documento),
      do: {:error, :ya_registrado},
      else: :ok
  end

  defp verificar_presente(albergue, documento) do
    if MapSet.member?(albergue.personas, documento),
      do: :ok,
      else: {:error, :persona_no_esta}
  end
end
