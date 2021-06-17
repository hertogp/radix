defmodule Radix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/hertogp/radix"

  def project do
    [
      app: :radix,
      version: @version,
      elixir: "~> 1.11",
      name: "Radix",
      description: "A bitwise radix tree that stores any value under a bitstring key",
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases()
    ]
  end

  defp aliases() do
    [docz: ["docs", &cp_images/1]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp package do
    %{
      licenses: ["MIT"],
      maintainers: ["hertogp"],
      links: %{"GitHub" => @url}
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp docs do
    [
      main: Radix,
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @url
    ]
  end

  defp cp_images(_) do
    # github image links: ![name](doc/img/a.png) - relative to root
    # hex image links:    ![name](img/a.png)     - relative to root/doc
    # - generate images in root/img, then
    # - process all dot files into images, and lastly
    # - copy root/img to root/doc/img.
    # The repo will only track the root/img and nothing inside root/doc
    File.mkdir_p!("doc/img")

    Path.wildcard("img/*.dot")
    |> Enum.map(fn file -> System.cmd("dot", ["-O", "-Tpng", file]) end)

    File.cp_r!("img/", "doc/img/")
  end
end
