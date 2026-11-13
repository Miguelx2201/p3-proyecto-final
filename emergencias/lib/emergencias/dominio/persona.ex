defmodule Emergencias.Dominio.Persona do
  @moduledoc """
  Persona afectada por la emergencia.

  El documento es único y sirve como identificador. El historial guarda cada
  cambio de estado como `%{fecha, de, a, usuario}`, con el más reciente primero;
  el primer registro (el más antiguo) tiene `de: nil`.

  Los estados siguen este orden y solo se puede avanzar (se permiten saltos
  hacia adelante):

      :sin_informacion -> :reportada -> :localizada -> :trasladada
        -> :en_albergue -> :reunificada

  Todas las funciones son puras: reciben una struct y devuelven una nueva.
  """

  alias Emergencias.{CSV, Util}

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]
  @filtros [:nombre, :documento, :zona, :estado]
  @edad_minima 0
  @edad_maxima 120

  @archivo "personas.csv"
  @cabecera "documento;nombre;edad;zona;estado"
  @archivo_historial "historial_personas.csv"
  @cabecera_historial "documento;fecha;de;a;usuario"

  defstruct documento: nil, nombre: nil, edad: nil, zona: nil, estado: nil, historial: []

  @type estado ::
          :sin_informacion | :reportada | :localizada | :trasladada | :en_albergue | :reunificada

  @type entrada_historial :: %{
          fecha: String.t(),
          de: estado() | nil,
          a: estado(),
          usuario: String.t()
        }

  @type t :: %__MODULE__{
          documento: String.t(),
          nombre: String.t(),
          edad: non_neg_integer(),
          zona: String.t(),
          estado: estado(),
          historial: [entrada_historial()]
        }

  @doc "Estados permitidos, en el orden en que una persona avanza."
  def estados, do: @estados

  # ---------------------------------------------------------------------------
  # Creación y cambio de estado
  # ---------------------------------------------------------------------------

  @doc """
  Crea una persona. El estado inicial puede ser cualquiera de los permitidos y
  queda como primer registro del historial (`de: nil`).

  Los textos se guardan sin espacios en los extremos y sin `;` ni saltos de línea.

  Errores: `:documento_vacio`, `:nombre_vacio`, `:edad_invalida` (entero fuera
  de 0..120 o no entero), `:zona_vacia`, `:estado_invalido`, `:usuario_vacio`.
  """
  def crear(documento, nombre, edad, zona, estado_inicial, usuario) do
    with {:ok, documento} <- validar_texto(documento, :documento_vacio),
         {:ok, nombre} <- validar_texto(nombre, :nombre_vacio),
         :ok <- validar_edad(edad),
         {:ok, zona} <- validar_texto(zona, :zona_vacia),
         :ok <- validar_estado(estado_inicial),
         {:ok, usuario} <- validar_texto(usuario, :usuario_vacio) do
      persona = %__MODULE__{
        documento: documento,
        nombre: nombre,
        edad: edad,
        zona: zona,
        estado: estado_inicial,
        historial: []
      }

      {:ok, registrar(persona, nil, estado_inicial, usuario)}
    end
  end

  @doc """
  Cambia el estado de la persona y agrega el cambio al inicio del historial.

  Errores: `:estado_invalido`, `:usuario_vacio`, `:mismo_estado`,
  `:transicion_invalida` (retroceder) y `:persona_invalida` (si el primer
  argumento no es una Persona).
  """
  def cambiar_estado(%__MODULE__{estado: actual} = persona, nuevo, usuario) do
    with :ok <- validar_estado(nuevo),
         {:ok, usuario} <- validar_texto(usuario, :usuario_vacio),
         :ok <- validar_transicion(actual, nuevo) do
      {:ok, registrar(persona, actual, nuevo, usuario)}
    end
  end

  def cambiar_estado(_persona, _nuevo, _usuario), do: {:error, :persona_invalida}

  defp registrar(persona, de, a, usuario) do
    entrada = %{fecha: Util.ahora(), de: de, a: a, usuario: usuario}
    %{persona | estado: a, historial: [entrada | persona.historial]}
  end

  defp validar_transicion(estado, estado), do: {:error, :mismo_estado}

  defp validar_transicion(actual, nuevo) do
    if transicion_permitida?(actual, nuevo), do: :ok, else: {:error, :transicion_invalida}
  end

  # Única regla del orden de estados. Para exigir pasos estrictamente
  # consecutivos basta cambiar la comparación por:
  #   posicion(nuevo) == posicion(actual) + 1
  defp transicion_permitida?(actual, nuevo), do: posicion(nuevo) > posicion(actual)

  defp posicion(estado), do: Enum.find_index(@estados, fn otro -> otro == estado end)

  # ---------------------------------------------------------------------------
  # Búsqueda

  @doc """
  Verdadero si la persona cumple todos los filtros dados.

  `filtros` es una keyword list con cualquiera de estas claves:

    * `nombre:` el nombre contiene el texto, sin distinguir mayúsculas.
    * `documento:` igual exacto.
    * `zona:` igual exacto al código de la zona.
    * `estado:` igual al átomo del estado.

  Una lista vacía coincide con cualquier persona. Un filtro con valor `nil` se
  ignora. Un filtro con clave desconocida o valor de tipo incorrecto hace que
  no coincida.
  """
  def coincide?(%__MODULE__{} = persona, filtros) when is_list(filtros) do
    Enum.all?(filtros, fn filtro -> cumple_filtro?(persona, filtro) end)
  end

  def coincide?(_persona, _filtros), do: false

  defp cumple_filtro?(_persona, {clave, nil}) when clave in @filtros, do: true

  defp cumple_filtro?(persona, {:nombre, texto}) when is_binary(texto) do
    persona.nombre
    |> String.downcase()
    |> String.contains?(texto |> String.trim() |> String.downcase())
  end

  defp cumple_filtro?(persona, {:documento, documento}) when is_binary(documento),
    do: persona.documento == String.trim(documento)

  defp cumple_filtro?(persona, {:zona, zona}) when is_binary(zona),
    do: persona.zona == String.trim(zona)

  defp cumple_filtro?(persona, {:estado, estado}) when is_atom(estado),
    do: persona.estado == estado

  defp cumple_filtro?(_persona, _filtro), do: false

end
