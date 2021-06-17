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
      description: "A path-compressed Patricia trie with one-way branching removed",
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
    # by copying the ./doc/img/*.png to ./img/ the links will work
    # on both hex.pm as well as github.  Copies dot-files as well since
    # supplying a image?(x,y) func to check if x doesn't end with dot, didnt
    # really seem to work...?
    File.mkdir_p!("img")
    File.cp_r!("doc/img/", "img/")
  end
end
