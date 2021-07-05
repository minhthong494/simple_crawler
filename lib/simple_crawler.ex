defmodule SimpleCrawler do
  @moduledoc """
  Documentation for `SimpleCrawler`.
  """
  alias Data.Movie

  @base_url "https://phimmoii.net/the-loai/hoat-hinh/trang-"
  @total_page 87
  @doc """
  Hello world.

  ## Examples

      iex> SimpleCrawler.hello()
      :world
  """
  def write do
    now =
      DateTime.utc_now()
      |> DateTime.add(7 * 3600)
      |> DateTime.truncate(:second)

    current_time_formatted =
      "#{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second}"

    data = %{
      crawled_at: current_time_formatted,
      total: 0,
      items: [%{a: 123, b: 456}]
    }

    File.write!("data.json", Poison.encode!(data), [:write])
  end

  def start(max_page \\ @total_page) do
    IO.puts("Starting ... ")
    start_ = DateTime.utc_now() |> DateTime.to_unix()

    now =
      DateTime.utc_now()
      |> DateTime.add(7 * 3600)
      |> DateTime.truncate(:second)

    current_time_formatted =
      "#{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second}"

    items =
      Enum.map(1..max_page, fn page ->
        fetch_and_parse_document(@base_url <> "#{page}.html")
        |> parse_listing_page()
      end)
      |> List.flatten()

    data = %{
      crawled_at: current_time_formatted,
      total: length(items),
      items: items
    }

    File.write!("data.json", Poison.encode!(data), [:write])

    IO.puts("-----------------------------")
    IO.puts("Total items: #{data.total}")
    IO.puts("Crawled at : #{data.crawled_at}")
    end_ = DateTime.utc_now() |> DateTime.to_unix()
    elap = end_ - start_
    IO.puts("Complete in #{elap} seconds")
  end

  def fetch_and_parse_document(url) do
    IO.puts("Fetching #{url}")

    body =
      case url do
        "#" ->
          IO.puts("Invalid url: #{url}")

        "" ->
          IO.puts("Invalid url: empty")

        _ ->
          case HTTPoison.get(url) do
            {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
              body

            _ ->
              IO.puts("Fetch data error: url = #{url}")
              []
          end
      end

    case Floki.parse_document(body) do
      {:ok, doc} ->
        doc

      _ ->
        IO.puts("Parse document error: #{url}")
        []
    end
  end

  @doc """
    Parse movies listing page
  """
  def parse_listing_page(document) do
    Floki.find(document, "li.movie-item > a")
    |> Floki.attribute("href")
    |> (fn urls ->
          Enum.map(urls, fn url ->
            fetch_and_parse_document(url)
            |> parse_movie_page(url)
          end)
        end).()
  end

  @doc """
    Parse detail of a movie and extract detail info
  """
  def parse_movie_page(document, url) do
    movie_image = Floki.find(document, ".movie-info .movie-image")

    thumnail_url =
      Floki.find(movie_image, "img")
      |> Floki.attribute("src")
      |> Floki.text()

    movie_detail = Floki.find(document, ".movie-info .movie-detail")

    title = movie_detail |> Floki.find(".movie-title a.title-1") |> Floki.text()

    year_str =
      movie_detail
      |> Floki.find(".movie-title .title-year")
      |> Floki.text()
      |> String.slice(2, 4)

    year =
      case year_str |> Integer.parse(10) do
        {year, _} -> year
        _ -> 0
      end

    watch_url =
      Floki.find(movie_image, "#btn-film-watch") |> Floki.attribute("href") |> Floki.text()

    status =
      movie_detail |> Floki.find(".movie-meta-info .movie-dl .movie-dd.status") |> Floki.text()

    %{full_series: is_full_series, number_of_episode: num_episode} =
      case parse_movie_status(status) do
        {:ok, res} ->
          res

        :error ->
          case fetch_and_parse_document(watch_url) |> parse_watch_page do
            {:ok, res} ->
              res

            :error ->
              IO.puts("fetch_and_parse_watch_page error")
              %{full_series: false, number_of_episode: 0}
          end
      end

    %Movie{
      title: title,
      link: url,
      full_series: is_full_series,
      number_of_episode: num_episode,
      thumnail: thumnail_url,
      year: year
    }
  end

  @doc """
    Example of movie status: "Tap 12/12 VIETSUB" or "N/A" or "Tap 16 VIETSUB"
    This function is intended to parse movie status to determine `full_series` and `number_of_episode` value.
    Assumption:
      movie status "Tap 12/12 VIETSUB" -> full_series = true, number_of_episode = 12
      movie status "Tap 10/12 VIETSUB" -> full_series = false, number_of_episode = 10
      movie status "Tap 12 VIETSUB"    -> not enough info, fetch and parse watch movie page
      movie status "N/A"               -> not enough info, fetch and parse watch movie page
  """
  def parse_movie_status(status) do
    # IO.puts("[debug] movie status #{status}")
    case String.split(status, " ")
         |> Enum.filter(fn x -> String.contains?(x, "/") end) do
      [value] when value != "N/A" ->
        [cur, total] =
          String.split(value, "/")
          |> Enum.map(fn x ->
            digits =
              String.codepoints(x)
              |> Enum.filter(fn c -> c >= "0" and c <= "9" end)
              |> List.to_string()

            {res, ""} = Integer.parse(digits, 10)
            res
          end)

        if cur == total do
          {:ok, %{full_series: true, number_of_episode: total}}
        else
          {:ok, %{full_series: false, number_of_episode: cur}}
        end

      _ ->
        :error
    end
  end

  @doc """
    Parse watch movie page to figure out number_of_episode
    Some movies do not have any episodes
    Assumption: cannot prove whether the movie has full series or not, so full_series = false
  """
  def parse_watch_page(document) do
    case Floki.find(document, "#list_episodes") do
      [{"ul", _, list_episode}] ->
        {:ok, %{full_series: false, number_of_episode: length(list_episode)}}

      _ ->
        :error
    end
  end
end
