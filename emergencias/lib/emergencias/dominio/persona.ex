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

  # ---------------------------------------------------------------------------
  # CSV: personas.csv

  @doc "Nombre del archivo de personas."
  def archivo_csv, do: @archivo

  @doc "Cabecera de `personas.csv`."
  def cabecera_csv, do: @cabecera

  @doc """
  Línea de `personas.csv` (sin el historial, que va en su propio archivo).

      iex> {:ok, p} = Emergencias.Dominio.Persona.crear("1094", "Andrés", 30, "centro", :localizada, "laura")
      iex> Emergencias.Dominio.Persona.a_linea(p)
      "1094;Andrés;30;centro;localizada"
  """
  def a_linea(%__MODULE__{} = persona) do
    CSV.unir([
      Util.sanitizar_texto(persona.documento),
      Util.sanitizar_texto(persona.nombre),
      persona.edad,
      Util.sanitizar_texto(persona.zona),
      persona.estado
    ])
  end

  @doc """
  Convierte una línea de `personas.csv` en `{:ok, persona}` con historial vacío
  (el historial se agrega con `con_historial/2`). Una línea corrupta da
  `{:error, razon}`.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [documento, nombre, edad, zona, estado] ->
        with {:ok, documento} <- validar_texto(documento, :documento_vacio),
             {:ok, nombre} <- validar_texto(nombre, :nombre_vacio),
             {:ok, edad} <- parsear_edad(edad),
             {:ok, zona} <- validar_texto(zona, :zona_vacia),
             {:ok, estado} <- parsear_estado(estado) do
          {:ok,
           %__MODULE__{
             documento: documento,
             nombre: nombre,
             edad: edad,
             zona: zona,
             estado: estado,
             historial: []
           }}
        end

      _otro ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_linea), do: {:error, :linea_invalida}

  # ---------------------------------------------------------------------------
  # CSV: historial_personas.csv (una fila por cambio)

  @doc "Nombre del archivo del historial de personas."
  def archivo_historial_csv, do: @archivo_historial

  @doc "Cabecera de `historial_personas.csv`."
  def cabecera_historial_csv, do: @cabecera_historial

  @doc """
  Filas `{documento, entrada}` del historial en orden cronológico (la más
  antigua primero), el mismo orden en que se agregan al archivo.
  """
  def filas_historial(%__MODULE__{documento: documento, historial: historial}) do
    historial
    |> Enum.reverse()
    |> Enum.map(fn entrada -> {documento, entrada} end)
  end

  @doc "Línea de `historial_personas.csv` para una fila `{documento, entrada}`."
  def historial_a_linea({documento, %{fecha: fecha, de: de, a: a, usuario: usuario}}) do
    CSV.unir([
      Util.sanitizar_texto(documento),
      fecha,
      estado_a_texto(de),
      a,
      Util.sanitizar_texto(usuario)
    ])
  end

  @doc """
  Convierte una línea de `historial_personas.csv` en `{:ok, {documento, entrada}}`.
  El campo `de` vacío se lee como `nil`.
  """
  def historial_de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [documento, fecha, de, a, usuario] ->
        with {:ok, documento} <- validar_texto(documento, :documento_vacio),
             {:ok, fecha} <- validar_texto(fecha, :fecha_vacia),
             {:ok, de} <- parsear_estado_anterior(de),
             {:ok, a} <- parsear_estado(a),
             {:ok, usuario} <- validar_texto(usuario, :usuario_vacio) do
          {:ok, {documento, %{fecha: fecha, de: de, a: a, usuario: usuario}}}
        end

      _otro ->
        {:error, :linea_invalida}
    end
  end

  def historial_de_linea(_linea), do: {:error, :linea_invalida}

  @doc """
  Reemplaza el historial de la persona con las filas de su documento.

  `filas` va en orden cronológico (como sale del archivo); el historial queda
  con el más reciente primero. Las filas de otros documentos se ignoran.
  """
  def con_historial(%__MODULE__{documento: documento} = persona, filas) when is_list(filas) do
    propias = for {^documento, entrada} <- filas, do: entrada
    %{persona | historial: Enum.reverse(propias)}
  end

end
