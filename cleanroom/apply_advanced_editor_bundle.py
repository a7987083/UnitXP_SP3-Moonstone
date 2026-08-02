#!/usr/bin/env python3
"""Install MoonMarker advanced M2 editor phase one after guild auth setup."""

from __future__ import annotations

import argparse
import base64
import hashlib
import subprocess
import zlib
from pathlib import Path

PAYLOADS = {
    "guild_lua": ("afc464fa5568a8c0ffe35beddb836419ef8bcb072f8712a090aec92d30eb69d5", """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"""),
    "auth_cpp": ("cd628ce284baf340fac630ea91219f659cc73e496903711ed03ab7d740504101", """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"""),
    "native_patch": ("0433278f5a802f6a3c71589d4054043be686150fe8be1bf903f3d7afc8d0ece3", """eNrlWllz2zgSfvevgP3gUJHM6LJ8e8ZjOzWpSnZddibZ3UxKRZOQxDVFann4SOL/vt0NggR4SUoy+7KplG2CDXSjL3zdhONOJmxnZ+rGzHrlW7F7z9/13/MoNu3Fgt2WhjZc3+GPzBo63dH+nml29/vO8Haf9brd0XC4sbOzU7HORrvdrlrr11/ZzqDXGbE2/Dxg8GgHfhTzx0XIotg5PIzcL3wcs7sbL4jPg8SP2QnbP9qoI3sD49VkEy+wUoKPQeg5v3N3OiMyc3dSRfmbFXGkvnIfuRcB4bBvdoGyXaI8c+4t3+bOO9e/sS2PA23X7C2htR4l7a7ZLdBqW1JmXFnx7C33p/EMpvWHXU3si49/v74QG3z94TUQXAwu4I/xP/75r+vfP7Jv8vnizevXf9xcwtwNlkSuP2XnIbdi/i5wuHcVBjZMvQ9c5yUzxuN45kYgpveyZdBYRzBk9swK4YEETVw/HvTHceuIzLk3RHPu7XV6e2jPKA4TO2ZoP/Z1g+E/oGcurPOGHAmUBbI8ozztlFhu+Srk9y5/SOe2ca6QDCbDptF6fuJ5izg8Ut/OcSeld+eDD9yOg5AtgsiN3cAHiq/P6cvbIPCYZaN3wvDE8iKuvgk5iBpec8t5KrwWZo1SU/aEh+QvnqyHCz4NOY/IKbK3wsJxiOpfgFVhGEXZkOoCO/wbpOUOmlPqjUS5dyP31lOkZDm3x4wJGuKgj4bodUcd1RC44AcegvpwWVK7kMYKQ+vpGHXdUcLtlE3x70gqq8o008JgSqsuq+2nsH72Ts5L/Mid+vDsBaCeqXDPc/DCKHWWSoKbxLZ5FPGUCDXQ6w1IBf39Tv9A6CBXuxc88PAssl3XUIfvLS/hLanykMdJ6ItB9FJ0UjKDH4Rzy4MQFWEDJjREZChrbYOnL5K4o48FSQyDLenQ4tG0PW6FRit1D3fCDJpr8vkifjJa7Ns3sZiJaQGeT2sSQ0uKrDppttyn7md2csJe/Pnni2xFOfYqHzInkOONF4cvWmzzRJX+8NCH6MlkVzSksnsGR1b3FvKIh/fcUDcgdzqBgDQwmzCbHQru2vJCqZnBiZKswVAwOE7ssW1F8bFGcWrYcn25fTHnmHUf+13cp3g+hee9y0qdKfIvkmg2vrXsO8OWmvpF6PCQZYyyTZfcQHgaubfic6kbKBZKyYTyt0xzq077FdIKpuSZc+dRcoLFpLvA8ZXva3s7e28H84UVcqNAv8OGHfy/ZcJyIMgJxVSJVb+S02A9ToMO/gdOfZ1Ruk3cDxhs3scciSkSjw878IKQzo+qsKO3f7PmeRyXjZIFcMEu+VyZWtFD1RPZpQQDv47Z3TlSR+lejli77SJLyj0jgjW9g4NOf4C5B88mdpu4nkP4450Fckjp5dm0nR1OnTSlG9tzImx96o0+Z9sRY596QwjdbIr5RWaonJXMEeuwpMOsk9uw+l/xfKsVOA9zIthOQ+8w3UQrC2fleBQiigVDy3EtH7O6cpi+1IKfCE+Nd+OrNy32ivX2a5ayYae+yBxgTngy0sVbuCBuu2KSOgX+rpuSmgSTacpHf9HDF+VhsuBOeXy3dh3iUMG5R1MUBCLH+5qTPBbeDrS3T4W3JQcTIUgOZi0W3pPqWHiob7MIfmaOinkNB8wUk2WgTGYxDb9IrqPPKRQQgbSPgdTvw1nezwJpFeYhh1TBwwVwEn5yw2NlCmLdU+NOHzxzHDiuopYidUd6qhZeJEBVeGU+j3svQqMGPbQb9CCQaF1Al5jkEV16VQzuEoEa0dm+2z+szgaORSWTiwklI3KIC/S5gksr1ZUFdVZYRlZVKZSIKquGElV9BVFtIj2UG6ykJ87yFgAZKuBSVS0MRryoXDrXk4WDgDq2pnxdb9aQYZXxCrhMYzV9C251GYZBSAOwtS0rnT+mPcBvPxgT162jIgYtAjFRDHpgnPPML+wkBEvE6UAmjVI35rRQVTivXe45x/T61KjzXMCU5xqQU1huZrohLKQKc1LrwBp+0qWqn1TQfTlWfwPTcstP4/Qsji179j64Jsd860ZxRaw2xWu3ddTA71q4V9ZUAI7q0Fq8VEbt9jRdhwrCH/Qm6UTPjENAqgoEPhdhsFhwByZ7/Cqg/f0ov3GEi41Ti23lHtsYL+TRFJiLwPMkxXWeUQyExCH/T8Kj+G1gOd93BGlZCfaPK53PuH0XlZF/mCaykt0v/SgJuSKbMH6utrsSReYLdZ6m7KzDelQVdZVwE7JApGw2ZV0tPJak5zhMuO5zyJvevg8B+9GhEBWtRzokYTSYRGZFdFIFUQhlVBxb+cvSUYWYaLd7gJho1O92et0egiKyik2NkLO4sSbqsKpGBYzRS63tYeeNQVg0grjDNg3VPB0mH0VHJ4cc3ZbWKEllKrh1hQhz2UhpLj1qq5fGWStXNqWyppFa20BeUeIucpTSkBag9HExg2wp7rxZ0VrKdVPkkosHNfImyeNGE9d3Y27kmL/V9PZptUW+VC1CGm2cn6tSJxMo57iie569PC23y1duPdXAG6JtrYD35J/LQJpaiDWjtPyhCathpGsWPlqKdWswTWXut3Mc8V2QrcmZAZk9IPIvHm/LTAXpVWnxLoPspROn8PUCgIYyskr9kYrbqQPPcGgDeFYAz18AhRuxA21nPLFcL0cs9UrVVJo1xY+ktuWJuTqyxfN2JdDZuAlBP567ERR69kzfx/JYXeZE9eW4Bl6yj0APM0hOWNdhldVh+c/nhmr3zFvMrLzOpcel6AUXbSqh6TjNF6XHpYtuk/xNy94gaIKZ+cpyZI2afKcHPpD9SpWEGKyBsV5moJqoQH7vzgHDWfPFGuzX4LNSObOUT31xn0LC74qh4bBVlxiaQkZg0rEHe8GwwU+1PztqyuzrKoyecnr/ogkJb7fYoTL0YMHJ6U/hVRQkIaSfLb2hn6oyr2rKuZFQ9gTOQUMFbiVwptU5m3XGAzyxNFs3IRiBcf630KbJL2KpnLHrE4Bc7Uz4KyDM0qy72j5EGe00+AlVUlRE13YDa+IBV8mK6OLX69iKk4hZVaP5wtWTwLsTL1Y7g2IkTxl1/giVao0/bhY7kumSenXaVLzq86SFq02v02qGbnADfZaCmGvRdGGGALmVWEun9IquU3Cmo0LhjZNk5S1KT/QXOk/X+UiIvRSt1KUPMcrnxsL3QfrEodEfA1QsBCIV7aP0Zkw3vY1ATi1838iEUJMs+YuaYsVAVYLN5i3EbQpqOLhSxmf15PoRv9SSVLHXmadTTHSFLuhKCHK1zttKiHpZ9tFKlbE9s/ypjq7LPcFUuj/IYsX240rpcPX27Eq4aWVco1rs5wAXrR9rEfiq0shP7kWvveHv3PRm86YLG1eLrCLZsz70vMxB6/BXt1Ve+3txmCLIs2jVyU4l8sN+XmS8uXBDSCODiwtQj80PXjKH/pDXG0Y9Smb7w4G4XbbWApJh+l1Kpj66JJA3SWEz4u5ZS57tlNQiuqGmwdwlUDhPGNlVM0MOV6QI2asHd96iVqZTe0N2VrzTOktvx95ae6O9g5Fp3u727V3noOF27KzqbuxM3OBDFR+Ii5SoNB+OnWhh2ZypxKTQdu3lSQFXvpbuOdbcbyzfa6y50Fh3rbL+hmNx2Cse59oVyExwVhI8H0nz9+Uj5IxI9sapNd7r9Gsb4+XuMbrDz22hL+9Yt+jK66tX6f1bwKFsip/4d6wkngUhXU3yArAAnOniXuUkDOZIBVyYjGpSrknrvJ+JJzZP8DsN0njkJ8zyHQYmBmzD8EIXA3OZ8775/96ip4IeFCdO9IjFoECELZnCH1ywRILf1khH6LRIQ3owf7h6leyv+Ty4l+zJ4DKHS0HMxgroaM3ChqJM4Rv4XPi2SLty09ZkAgaUew7gBxDwe+6ba+Jr9PP/AtIGSvo="""),
}


def decode_payload(name: str) -> bytes:
    expected, encoded = PAYLOADS[name]
    raw = zlib.decompress(base64.b64decode(encoded))
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected:
        raise RuntimeError(f"{name} checksum mismatch: {actual}")
    return raw


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--addon", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    addon_root = Path(args.addon) / "MoonMarker"

    patch_bytes = decode_payload("native_patch")
    subprocess.run(
        ["patch", "--batch", "-p1", "-d", str(upstream)],
        input=patch_bytes,
        check=True,
    )

    header_path = upstream / "moonMarker.h"
    header = header_path.read_text(encoding="utf-8-sig")
    header = replace_once(
        header,
        "bool placeRemote(const std::string& colorName, const C3Vector& position,\n"
        "                 bool renderOverlay = true);\n",
        "bool placeRemote(const std::string& colorName, const C3Vector& position,\n"
        "                 bool renderOverlay = true);\n\n"
        "// Returns the safe world-ground position below the current mouse cursor\n"
        "// without creating or replacing a normal color marker.\n"
        "bool cursorGroundPosition(C3Vector& position);\n",
        "moonMarker cursor declaration",
    )
    header_path.write_text(header, encoding="utf-8", newline="\n")

    source_path = upstream / "moonMarker.cpp"
    source = source_path.read_text(encoding="utf-8-sig")
    source = replace_once(
        source,
        "bool placeAtCursor(const std::string& colorName, C3Vector& placedPosition,\n",
        "bool cursorGroundPosition(C3Vector& position) {\n"
        "    return cursorWorldIntersection(position);\n"
        "}\n\n"
        "bool placeAtCursor(const std::string& colorName, C3Vector& placedPosition,\n",
        "moonMarker cursor implementation",
    )
    source_path.write_text(source, encoding="utf-8", newline="\n")

    (upstream / "MoonMarkerGuildAuth.cpp").write_bytes(decode_payload("auth_cpp"))
    (addon_root / "GuildAdvanced.lua").write_bytes(decode_payload("guild_lua"))

    required_cpp = (
        "advancedPreviewCommand",
        "createAdvancedPreview",
        "cursorGroundPosition",
        "advancedSetTransformCommand",
    )
    generated_cpp = (upstream / "MoonMarkerGuildAuth.cpp").read_text(encoding="utf-8")
    for token in required_cpp:
        if token not in generated_cpp:
            raise RuntimeError(f"advanced auth source missing token: {token}")

    generated_lua = (addon_root / "GuildAdvanced.lua").read_text(encoding="utf-8")
    for token in (
        "MoonMarkerAdvancedFrame",
        "MoonMarker.Advanced.PreviewM2",
        "拖动这里旋转当前预览",
        "advancedFavorites",
    ):
        if token not in generated_lua:
            raise RuntimeError(f"advanced guild Lua missing token: {token}")
    if "GetGuildInfo" in generated_lua:
        raise RuntimeError("advanced Lua must not make the authorization decision")


if __name__ == "__main__":
    main()
