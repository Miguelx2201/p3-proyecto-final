defmodule Emergencias.Dominio.Mascota do
  @moduledoc """
  Reporte de una mascota perdida o encontrada después del terremoto.

  Es una struct inmutable: cada función recibe la mascota y devuelve una nueva.
  Las funciones devuelven `{:ok, valor}` o `{:error, razon}` y nunca lanzan
  excepciones.

  Ciclo de vida del reporte (`estado`):

      activa ───────────────► posible_coincidencia
        │  ◄───────────────────────┘     │
        └──────────► resuelta ◄──────────┘

  Un reporte `:resuelta` ya no cambia: cualquier intento devuelve
  `{:error, :ya_resuelta}`.
  """

  alias Emergencias.{CSV, Util}

  @tipos [:perdida, :encontrada]
  @tamanos [:pequeno, :mediano, :grande]
  @estados [:activa, :posible_coincidencia, :resuelta]

  @transiciones %{
    activa: [:posible_coincidencia, :resuelta],
    posible_coincidencia: [:activa, :resuelta],
    resuelta: []
  }

  @archivo "mascotas.csv"
  @cabecera "id;tipo;especie;nombre;caracteristicas;color;tamano;zona;contacto;estado"

  @type tipo :: :perdida | :encontrada
  @type tamano :: :pequeno | :mediano | :grande
  @type estado :: :activa | :posible_coincidencia | :resuelta

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          especie: String.t(),
          nombre: String.t() | nil,
          caracteristicas: String.t(),
          color: String.t(),
          tamano: tamano(),
          zona: String.t(),
          contacto: String.t(),
          estado: estado()
        }

  defstruct id: nil,
            tipo: nil,
            especie: nil,
            nombre: nil,
            caracteristicas: "",
            color: nil,
            tamano: nil,
            zona: nil,
            contacto: nil,
            estado: :activa

  @doc "Tipos de reporte permitidos."
  def tipos, do: @tipos

  @doc "Tamaños permitidos."
  def tamanos, do: @tamanos

  @doc "Estados posibles de un reporte."
  def estados, do: @estados

  # ---------------------------------------------------------------------------
  # Creación
  # ---------------------------------------------------------------------------

  @doc """
  Crea un reporte de mascota en estado `:activa`.

  Validaciones, en este orden:

    * `tipo` debe ser `:perdida` o `:encontrada` → si no, `{:error, :tipo_invalido}`.
    * `tamano` debe ser `:pequeno`, `:mediano` o `:grande` → si no, `{:error, :tamano_invalido}`.
    * `especie` no vacía → si no, `{:error, :especie_vacia}`.
    * `color` no vacío → si no, `{:error, :color_vacio}`.
    * `contacto` no vacío → si no, `{:error, :contacto_vacio}`.

  `nombre` queda en `nil` si viene `nil`, vacío o con el texto `desconocido`
  (sin importar mayúsculas). `caracteristicas` vacío o `nil` queda como `""`.
  Todos los textos se sanitizan para el CSV.

      iex> {:ok, m} = Emergencias.Dominio.Mascota.crear("M001", :perdida, "perro", "Desconocido", nil, "negra", :mediano, "centro", "300")
      iex> {m.nombre, m.caracteristicas, m.estado}
      {nil, "", :activa}
  """
  def crear(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    with :ok <- validar_valor(tipo, @tipos, :tipo_invalido),
         :ok <- validar_valor(tamano, @tamanos, :tamano_invalido),
         :ok <- validar_no_vacio(especie, :especie_vacia),
         :ok <- validar_no_vacio(color, :color_vacio),
         :ok <- validar_no_vacio(contacto, :contacto_vacio) do
      {:ok,
       %__MODULE__{
         id: Util.sanitizar_texto(id),
         tipo: tipo,
         especie: Util.sanitizar_texto(especie),
         nombre: normalizar_nombre(nombre),
         caracteristicas: Util.sanitizar_texto(caracteristicas),
         color: Util.sanitizar_texto(color),
         tamano: tamano,
         zona: Util.sanitizar_texto(zona),
         contacto: Util.sanitizar_texto(contacto),
         estado: :activa
       }}
    end
  end

  defp validar_valor(valor, permitidos, razon) do
    if valor in permitidos, do: :ok, else: {:error, razon}
  end

  defp validar_no_vacio(texto, razon) do
    if is_binary(texto) and not Util.vacio?(Util.sanitizar_texto(texto)),
      do: :ok,
      else: {:error, razon}
  end

  defp normalizar_nombre(nombre) do
    limpio = Util.sanitizar_texto(nombre)

    if limpio == "" or String.downcase(limpio) == "desconocido", do: nil, else: limpio
  end

  # ---------------------------------------------------------------------------
  # Transiciones de estado
  # ---------------------------------------------------------------------------

  @doc """
  Cambia el estado del reporte según la tabla de transiciones.

    * `activa` → `posible_coincidencia`, `resuelta`
    * `posible_coincidencia` → `activa`, `resuelta`
    * `resuelta` → ninguna: devuelve `{:error, :ya_resuelta}`.

  Cualquier otro cambio (incluido pasar al mismo estado o a un estado que no
  existe) devuelve `{:error, :transicion_invalida}`.
  """
  def cambiar_estado(%__MODULE__{estado: :resuelta}, _nuevo), do: {:error, :ya_resuelta}

  def cambiar_estado(%__MODULE__{estado: actual} = mascota, nuevo) do
    if nuevo in Map.get(@transiciones, actual, []),
      do: {:ok, %{mascota | estado: nuevo}},
      else: {:error, :transicion_invalida}
  end

  # ---------------------------------------------------------------------------
  # CSV (mascotas.csv)
  # ---------------------------------------------------------------------------

  @doc "Nombre del archivo CSV de las mascotas."
  def archivo, do: @archivo

  @doc "Cabecera del archivo CSV."
  def cabecera, do: @cabecera

  @doc """
  Convierte la mascota en una línea CSV. Un `nombre` desconocido (`nil`) se
  guarda como campo vacío.
  """
  def a_linea(%__MODULE__{} = mascota) do
    CSV.unir([
      Util.sanitizar_texto(mascota.id),
      Atom.to_string(mascota.tipo),
      Util.sanitizar_texto(mascota.especie),
      Util.sanitizar_texto(mascota.nombre),
      Util.sanitizar_texto(mascota.caracteristicas),
      Util.sanitizar_texto(mascota.color),
      Atom.to_string(mascota.tamano),
      Util.sanitizar_texto(mascota.zona),
      Util.sanitizar_texto(mascota.contacto),
      Atom.to_string(mascota.estado)
    ])
  end

  @doc """
  Convierte una línea CSV en mascota. Aplica las mismas validaciones de
  `crear/9`; si la línea no tiene 10 campos o algún valor no es válido devuelve
  `{:error, razon}`.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado] ->
        with {:ok, tipo} <- parsear(tipo, @tipos, :tipo_invalido),
             {:ok, tamano} <- parsear(tamano, @tamanos, :tamano_invalido),
             {:ok, estado} <- parsear(estado, @estados, :estado_invalido),
             {:ok, mascota} <-
               crear(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
          {:ok, %{mascota | estado: estado}}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}

  defp parsear(texto, permitidos, razon) do
    case Util.parsear_enum(texto, permitidos) do
      {:ok, valor} -> {:ok, valor}
      {:error, _} -> {:error, razon}
    end
  end
end
