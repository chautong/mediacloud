"""tests for mediawords.util.html"""

import mediawords.languages.en
from mediawords.util.html import link_canonical_url_from_html, meta_refresh_url_from_html, html_strip
from mediawords.util.log import create_logger
import mediawords.util.html
import mediawords.util.paths

log = create_logger(__name__)


# noinspection SpellCheckingInspection
def test_link_canonical_url_from_html():
    # No <link rel="canonical" />
    assert link_canonical_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') is None

    # Basic HTML <link rel="canonical">
    assert link_canonical_url_from_html(html="""
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <LINK REL="stylesheet" TYPE="text/css" HREF="theme.css">
            <LINK REL="canonical" HREF="http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML <meta http-equiv="refresh" />
    assert link_canonical_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
            <link rel="canonical" href="http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Relative path (base URL with trailing slash -- valid, but not a good practice)
    assert link_canonical_url_from_html(html="""
        <link rel="canonical" href="second/third/" />
    """, base_url='http://example.com/first/') == 'http://example.com/first/second/third/'

    # Relative path (base URL without trailing slash -- valid, but not a good practice)
    assert link_canonical_url_from_html(html="""
        <link rel="canonical" href="second/third/" />
    """, base_url='http://example.com/first') == 'http://example.com/second/third/'

    # Absolute path (valid, but not a good practice)
    assert link_canonical_url_from_html(html="""
        <link rel="canonical" href="/first/second/third/" />
    """, base_url='http://example.com/fourth/fifth/') == 'http://example.com/first/second/third/'

    # Invalid URL without base URL
    assert link_canonical_url_from_html(html="""
        <link rel="canonical" href="/first/second/third/" />
    """) is None


# noinspection SpellCheckingInspection
def test_meta_refresh_url_from_html():
    # No <meta http-equiv="refresh" />
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') is None

    # Basic HTML <meta http-equiv="refresh">
    assert meta_refresh_url_from_html(html="""
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=UTF-8">
            <META HTTP-EQUIV="refresh" CONTENT="0; URL=http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML <meta http-equiv="refresh" />
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="0; url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML sans the seconds part
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML with quoted url
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url='http://example.com/'" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML with reverse quoted url
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content='url="http://example.com/"' />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Relative path (base URL with trailing slash)
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=second/third/" />
    """, base_url='http://example.com/first/') == 'http://example.com/first/second/third/'

    # Relative path (base URL without trailing slash)
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=second/third/" />
    """, base_url='http://example.com/first') == 'http://example.com/second/third/'

    # Absolute path
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
    """, base_url='http://example.com/fourth/fifth/') == 'http://example.com/first/second/third/'

    # Invalid URL without base URL
    assert meta_refresh_url_from_html("""
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
    """) is None


def test_sententize_block_level_tags() -> None:
    """Test _new_lines_around_block_level_tags()."""
    assert mediawords.util.html._sententize_block_level_tags('<h1>foo</h1>') == '\n\n<h1>foo.</h1>\n\n'


def test_html_strip() -> None:
    """Test html_strip()."""
    assert html_strip("<strong>Hellonot </strong>") == "Hellonot"

    assert html_strip("<script>delete</script><p>body</p>") == "body."

    assert html_strip("<title>delete</title><p>content</p>") == "content."

    assert html_strip("<title>delete</title><p>content</p>", include_title=True) == "delete. content."

    assert html_strip("<p>foo\xAD</p>") == "foo."

    assert html_strip("&amp;&quot;") == '&"'

    html_path = mediawords.util.paths.mc_root_path() + '/mediacloud/test-data/html/strip.html'
    with open(html_path, 'r', encoding='utf8') as fh:
        html = fh.read()

    # just santiy test here to make sure there are no errors without having to use a fixture
    got_text = html_strip(html)
    assert(len(got_text) > 0.05 * len(html))
    assert '<' not in got_text
