defmodule Emergencias.Persistencia do
  @moduledoc """
  Punto único para guardar y cargar las entidades en archivos CSV.

  Usa `Emergencias.CSV` para leer y escribir, y las funciones `to_linea`/`a_linea`
  y `de_linea` de cada entidad para convertir. La carpeta de datos sale de
  `Emergencias.CSV.ruta/1` (`:data_dir`).

  Ninguna función lanza excepciones:

    * `guardar_x(lista)` devuelve `:ok` o `{:error, razon}`.
    * `cargar_x()` devuelve `{:ok, lista}` o `{:error, razon}`. Un archivo que no
      existe da `{:ok, []}`; una línea corrupta da `{:error, {:linea_invalida, n}}`.

  `guardar_x/1` reescribe el archivo completo (ver `Emergencias.CSV.escribir/4`).
  Regla del proyecto: cada archivo tiene un solo proceso escritor (el GenServer
  dueño), por eso aquí no se hace ningún control de concurrencia.

  `movimientos.csv` solo se agrega al final con `agregar_movimiento/1`.
  """

  alias Emergencias.CSV
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Movimiento
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Sector
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Dominio.Zona
  alias Emergencias.Util

  @archivo_usuarios "usuarios.csv"
  @archivo_zonas "zonas.csv"
  @archivo_sectores "sectores.csv"
  @archivo_puntos "puntos.csv"
  @archivo_recursos "recursos.csv"
  @archivo_movimientos "movimientos.csv"

  @cabecera_zonas "codigo;nombre;nivel;personas"
  @cabecera_sectores "zona;codigo;nombre;personas"
  @cabecera_puntos "zona;sector;codigo;nombre;personas"

  # ---------------------------------------------------------------------------
  # Usuarios
  # ---------------------------------------------------------------------------

  @doc "Guarda todos los usuarios en `usuarios.csv`. El campo `conectado` no se guarda."
  @spec guardar_usuarios([Usuario.t()]) :: :ok | {:error, term()}
  def guardar_usuarios(usuarios),
    do: guardar(@archivo_usuarios, Usuario.cabecera(), usuarios, Usuario, &Usuario.to_linea/1)

  @doc "Carga los usuarios de `usuarios.csv`, todos con `conectado: false`."
  @spec cargar_usuarios() :: {:ok, [Usuario.t()]} | {:error, term()}
  def cargar_usuarios, do: cargar(@archivo_usuarios, &Usuario.de_linea/1)

  # ---------------------------------------------------------------------------
  # Zonas (árbol Zona -> Sectores -> Puntos de atención en tres archivos)
  # ---------------------------------------------------------------------------

  @doc """
  Guarda el árbol de zonas: una fila por zona en `zonas.csv`, una por sector en
  `sectores.csv` (con el código de su zona) y una por punto de atención en
  `puntos.csv` (con los códigos de su zona y su sector).

  Son tres archivos y se escriben uno tras otro: si el segundo o el tercero
  falla, el primero ya quedó reescrito.
  """
  @spec guardar_zonas([Zona.t()]) :: :ok | {:error, term()}
  def guardar_zonas(zonas) do
    with :ok <- validar_arbol(zonas),
         :ok <-
           CSV.escribir(CSV.ruta(@archivo_zonas), @cabecera_zonas, zonas, &Zona.to_linea/1),
         :ok <-
           CSV.escribir(
             CSV.ruta(@archivo_sectores),
             @cabecera_sectores,
             filas_sectores(zonas),
             &sector_a_linea/1
           ) do
      CSV.escribir(
        CSV.ruta(@archivo_puntos),
        @cabecera_puntos,
        filas_puntos(zonas),
        &punto_a_linea/1
      )
    end
  end

  @doc """
  Carga los tres archivos y reconstruye el árbol de zonas, en el mismo orden en
  que se guardaron.

  Errores: `{:error, :sector_huerfano}` si un sector apunta a una zona que no
  está en `zonas.csv`, y `{:error, :punto_huerfano}` si un punto apunta a un
  sector que no existe en esa zona.
  """
  @spec cargar_zonas() :: {:ok, [Zona.t()]} | {:error, term()}
  def cargar_zonas do
    with {:ok, zonas} <- cargar(@archivo_zonas, &Zona.de_linea/1),
         {:ok, sectores} <- cargar(@archivo_sectores, &sector_de_linea/1),
         {:ok, puntos} <- cargar(@archivo_puntos, &punto_de_linea/1),
         :ok <- validar_padres(zonas, sectores, puntos) do
      {:ok, armar_arbol(zonas, sectores, puntos)}
    end
  end

  defp validar_arbol(zonas) do
    if lista_de?(zonas, Zona) and Enum.all?(zonas, &sectores_validos?/1) do
      :ok
    else
      {:error, :lista_invalida}
    end
  end

  defp sectores_validos?(zona) do
    lista_de?(zona.sectores, Sector) and
      Enum.all?(zona.sectores, fn sector -> lista_de?(sector.puntos_atencion, PuntoAtencion) end)
  end

  defp filas_sectores(zonas) do
    for zona <- zonas, sector <- zona.sectores, do: {zona.codigo, sector}
  end

  defp filas_puntos(zonas) do
    for zona <- zonas,
        sector <- zona.sectores,
        punto <- sector.puntos_atencion,
        do: {zona.codigo, sector.codigo, punto}
  end

  # sectores.csv: zona;codigo;nombre;personas. Los tres últimos campos son los
  # de `Sector.to_linea/1`.
  defp sector_a_linea({zona, sector}),
    do: CSV.unir([Util.sanitizar_texto(zona), Sector.to_linea(sector)])

  defp sector_de_linea(linea) when is_binary(linea) do
    with [zona | campos] when campos != [] <- CSV.separar(linea),
         false <- Util.vacio?(zona),
         {:ok, sector} <- Sector.de_linea(CSV.unir(campos)) do
      {:ok, {zona, sector}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  # puntos.csv: zona;sector;codigo;nombre;personas. Los tres últimos campos son
  # los de `PuntoAtencion.to_linea/1`.
  defp punto_a_linea({zona, sector, punto}) do
    CSV.unir([
      Util.sanitizar_texto(zona),
      Util.sanitizar_texto(sector),
      PuntoAtencion.to_linea(punto)
    ])
  end

  defp punto_de_linea(linea) when is_binary(linea) do
    with [zona, sector | campos] when campos != [] <- CSV.separar(linea),
         false <- Util.vacio?(zona),
         false <- Util.vacio?(sector),
         {:ok, punto} <- PuntoAtencion.de_linea(CSV.unir(campos)) do
      {:ok, {zona, sector, punto}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  defp validar_padres(zonas, sectores, puntos) do
    codigos_zona = MapSet.new(zonas, fn zona -> zona.codigo end)
    pares = MapSet.new(sectores, fn {zona, sector} -> {zona, sector.codigo} end)

    cond do
      not Enum.all?(sectores, fn {zona, _sector} -> MapSet.member?(codigos_zona, zona) end) ->
        {:error, :sector_huerfano}

      not Enum.all?(puntos, fn {zona, sector, _punto} -> MapSet.member?(pares, {zona, sector}) end) ->
        {:error, :punto_huerfano}

      true ->
        :ok
    end
  end

  defp armar_arbol(zonas, sectores, puntos) do
    sectores_por_zona = Enum.group_by(sectores, fn {zona, _sector} -> zona end)
    puntos_por_sector = Enum.group_by(puntos, fn {zona, sector, _punto} -> {zona, sector} end)

    Enum.map(zonas, fn zona ->
      sectores_de_zona =
        sectores_por_zona
        |> Map.get(zona.codigo, [])
        |> Enum.map(fn {_zona, sector} ->
          puntos_de_sector =
            puntos_por_sector
            |> Map.get({zona.codigo, sector.codigo}, [])
            |> Enum.map(fn {_zona, _sector, punto} -> punto end)

          %{sector | puntos_atencion: puntos_de_sector}
        end)

      %{zona | sectores: sectores_de_zona}
    end)
  end

  # ---------------------------------------------------------------------------
  # Necesidades, recursos, mascotas y mensajes
  # ---------------------------------------------------------------------------

  @doc "Guarda todas las necesidades en `necesidades.csv`."
  @spec guardar_necesidades([Necesidad.t()]) :: :ok | {:error, term()}
  def guardar_necesidades(necesidades),
    do:
      guardar(
        Necesidad.archivo(),
        Necesidad.cabecera(),
        necesidades,
        Necesidad,
        &Necesidad.a_linea/1
      )

  @doc "Carga las necesidades de `necesidades.csv`."
  @spec cargar_necesidades() :: {:ok, [Necesidad.t()]} | {:error, term()}
  def cargar_necesidades, do: cargar(Necesidad.archivo(), &Necesidad.de_linea/1)

  @doc "Guarda todos los recursos en `recursos.csv`."
  @spec guardar_recursos([Recurso.t()]) :: :ok | {:error, term()}
  def guardar_recursos(recursos),
    do: guardar(@archivo_recursos, Recurso.cabecera(), recursos, Recurso, &Recurso.a_linea/1)

  @doc "Carga los recursos de `recursos.csv`."
  @spec cargar_recursos() :: {:ok, [Recurso.t()]} | {:error, term()}
  def cargar_recursos, do: cargar(@archivo_recursos, &Recurso.de_linea/1)

  @doc "Guarda todas las mascotas en `mascotas.csv`."
  @spec guardar_mascotas([Mascota.t()]) :: :ok | {:error, term()}
  def guardar_mascotas(mascotas),
    do: guardar(Mascota.archivo(), Mascota.cabecera(), mascotas, Mascota, &Mascota.a_linea/1)

  @doc "Carga las mascotas de `mascotas.csv`."
  @spec cargar_mascotas() :: {:ok, [Mascota.t()]} | {:error, term()}
  def cargar_mascotas, do: cargar(Mascota.archivo(), &Mascota.de_linea/1)

  @doc "Guarda todos los mensajes en `mensajes.csv`."
  @spec guardar_mensajes([Mensaje.t()]) :: :ok | {:error, term()}
  def guardar_mensajes(mensajes),
    do:
      guardar(
        Mensaje.archivo_csv(),
        Mensaje.cabecera_csv(),
        mensajes,
        Mensaje,
        &Mensaje.a_linea/1
      )

  @doc "Carga los mensajes de `mensajes.csv`."
  @spec cargar_mensajes() :: {:ok, [Mensaje.t()]} | {:error, term()}
  def cargar_mensajes, do: cargar(Mensaje.archivo_csv(), &Mensaje.de_linea/1)

  # ---------------------------------------------------------------------------
  # Personas (personas.csv + historial_personas.csv)
  # ---------------------------------------------------------------------------

  @doc """
  Guarda las personas en `personas.csv` y su historial en
  `historial_personas.csv` (una fila por cambio de estado, la más antigua
  primero dentro de cada persona).

  Son dos archivos y se escriben uno tras otro: si el segundo falla, el primero
  ya quedó reescrito.
  """
  @spec guardar_personas([Persona.t()]) :: :ok | {:error, term()}
  def guardar_personas(personas) do
    with :ok <- validar_lista(personas, Persona),
         :ok <-
           CSV.escribir(
             CSV.ruta(Persona.archivo_csv()),
             Persona.cabecera_csv(),
             personas,
             &Persona.a_linea/1
           ) do
      CSV.escribir(
        CSV.ruta(Persona.archivo_historial_csv()),
        Persona.cabecera_historial_csv(),
        Enum.flat_map(personas, &Persona.filas_historial/1),
        &Persona.historial_a_linea/1
      )
    end
  end

  @doc """
  Carga las personas y une a cada una su historial por `documento`
  (con `Emergencias.Dominio.Persona.con_historial/2`). Las filas del historial
  cuyo documento no corresponde a ninguna persona se ignoran.
  """
  @spec cargar_personas() :: {:ok, [Persona.t()]} | {:error, term()}
  def cargar_personas do
    with {:ok, personas} <- cargar(Persona.archivo_csv(), &Persona.de_linea/1),
         {:ok, filas} <- cargar(Persona.archivo_historial_csv(), &Persona.historial_de_linea/1) do
      por_documento = Enum.group_by(filas, fn {documento, _entrada} -> documento end)

      {:ok,
       Enum.map(personas, fn persona ->
         Persona.con_historial(persona, Map.get(por_documento, persona.documento, []))
       end)}
    end
  end

  # ---------------------------------------------------------------------------
  # Movimientos (solo se agrega al final)
  # ---------------------------------------------------------------------------

  @doc """
  Agrega un movimiento al final de `movimientos.csv` (lo crea con su cabecera si
  no existe). El movimiento ya debe tener `id`: sin él la línea no se podría
  volver a leer, así que se devuelve `{:error, :id_requerido}`.
  """
  @spec agregar_movimiento(Movimiento.t()) :: :ok | {:error, term()}
  def agregar_movimiento(%Movimiento{id: id} = movimiento) when is_binary(id) do
    if Util.vacio?(id) do
      {:error, :id_requerido}
    else
      CSV.agregar(
        CSV.ruta(@archivo_movimientos),
        Movimiento.cabecera(),
        movimiento,
        &Movimiento.a_linea/1
      )
    end
  end

  def agregar_movimiento(%Movimiento{}), do: {:error, :id_requerido}
  def agregar_movimiento(_otro), do: {:error, :movimiento_invalido}

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp guardar(archivo, cabecera, entidades, modulo, a_linea) do
    with :ok <- validar_lista(entidades, modulo) do
      CSV.escribir(CSV.ruta(archivo), cabecera, entidades, a_linea)
    end
  end

  defp cargar(archivo, de_linea), do: CSV.leer(CSV.ruta(archivo), de_linea)

  defp validar_lista(entidades, modulo) do
    if lista_de?(entidades, modulo), do: :ok, else: {:error, :lista_invalida}
  end

  defp lista_de?(entidades, modulo) do
    is_list(entidades) and Enum.all?(entidades, &match?(%{__struct__: ^modulo}, &1))
  end
end
