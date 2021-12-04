defmodule Radix.MixProject do
  use Mix.Project

  # Before publishing to Hex:
  # - mix test
  # - mix docz
  # - mix dialyzer
  # - ensure right version tag in mix.exs, README.md and CHANGELOG.md
  # - git tag -a vx.y.z -m 'Release vx.y.z'
  # - git push --tags
  # mix hex.publish

  @version "0.4.0"
  @source_url "https://github.com/hertogp/radix"

  def project do
    [
      app: :radix,
      version: @version,
      elixir: "~> 1.11",
      name: "Radix",
      description:
        "A bitwise radix tree for prefix based matching on bitstring keys of any length.",
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases()
    ]
  end

  defp aliases() do
    [docs: ["docs", &gen_images/1]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp package do
    %{
      licenses: ["MIT"],
      maintainers: ["hertogp"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/radix/changelog.html"
      }
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "LICENSE.md": [title: "License"],
        "CHANGELOG.md": []
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      assets: "assets",
      formatters: ["html"]
    ]
  end

  defp gen_images(_) do
    for dot <- Path.wildcard("assets/*.dot") do
      System.cmd("dot", ["-O", "-Tpng", dot])
    end
  end

  # defp cp_images(_) do
  #  # the repo doesn't track `/doc/` or any of its subdirectories.  Github
  #  # links work if documentation links to images like `![xx](img/a.png)`
  #  #
  #  # While on hex.pm, image links are taken to be relative to the repo's
  #  # root/doc directory.  Hence, the img/*.dot files are processed into
  #  # img/*.png files, after which the img/*.png files are copied to
  #  # doc/img/*.png so everybody is happy.
  #  #
  #  # Also note, that doing it this way (img/*.png -> doc/img/*.png) keeps
  #  # the CI from failing, since the doc/img dir does not exist so doctests
  #  # that simply try to write to e.g. doc/img/a.png will fail.

  #  # ensure the (untracked) doc/img directory for hex.pm
  #  Path.join("doc", "img")
  #  |> File.mkdir_p!()

  #  # process all img/*.dot files into img/*.dot.png image files
  #  Path.wildcard("img/*.dot")
  #  |> Enum.map(fn file -> System.cmd("dot", ["-O", "-Tpng", file]) end)

  #  # copy img/*.png to doc/img/*.png
  #  Path.wildcard("img/*.png")
  #  |> Enum.map(fn src -> {src, Path.join("doc", src)} end)
  #  |> Enum.map(fn {src, dst} -> File.cp!(src, dst) end)
  # end
end
