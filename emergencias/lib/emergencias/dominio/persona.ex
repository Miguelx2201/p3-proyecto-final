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

end
