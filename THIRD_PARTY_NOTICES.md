# Third-party notices

SmartLight implements local wire protocols in Dart using Pointy Castle and crypto.

Optional personal Android pairing builds include the proprietary Tuya Smart Life App SDK 7.8.0 and an app-specific security component. Tuya owns and licenses those components separately under its [Software License and Service Agreement](https://images.tuyacn.com/smart/docs/Software_License_and_Service_Agreement_EN.html). They are not covered by the local protocol references' MIT licenses. SDK credentials and the security component are excluded from this repository and ordinary CI builds. Tuya's development edition is for personal/noncommercial development and is not an app-store distribution license.
Protocol format/algorithm references:

- TinyTuya, https://github.com/jasonacox/tinytuya (MIT). Tuya protocol documentation, framing, session negotiation, light profiles. Independent test vectors generated with TinyTuya 1.20.0 and PyCryptodome; generator: tool/generate_protocol_vectors.py.
- PyP100, https://github.com/fishbigger/TapoP100 (MIT). Legacy RSA key exchange, AES-CBC secure passthrough, and login v1 wire format.
- esp-tapo, https://github.com/Alejandro12120/esp-tapo (MIT). KLAP session derivation and encrypted transport description. SmartLight additionally verifies response signatures.
- python-kasa's public L920 fixtures and UDP discovery packet format (https://github.com/python-kasa/python-kasa/blob/master/kasa/discover.py) were consulted for device capability and wire-format facts; no Python runtime or python-kasa source is bundled.
- Tapo Rust library countdown request/response definitions (https://github.com/mihai-dinculescu/tapo/tree/main/tapo/src/requests) and PyP100 were consulted for timer wire-format facts. No Rust source or runtime is bundled. Tuya's official lighting DP definition (https://developer.tuya.com/en/docs/iot/product-function-definition?_source=github&id=K9s9rhj576ypf) and panel countdown semantics (https://developer.tuya.com/en/docs/iot/product-panel-dp-interactive-description?_source=c1bd9002df6536b2e2ca8d917825d4e5&id=K9s9rhiowe806) document optional DP26, its limits and power-change cancellation.


MIT License

Copyright (c) 2024 Jason Cox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


MIT License

Copyright (c) 2026 esp-tapo contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


MIT License — PyP100

Copyright 2022 Toby Johnson

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


Tuya EZ desktop pairing encoding is adapted from @tuyapi/link 0.5.0, https://github.com/TuyaAPI/link. Tuya UDP discovery uses the TinyTuya protocol reference above.

MIT License

Copyright (c) 2018 TuyAPI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Inter typography

Inter 4.1 by Rasmus Andersson, bundled under the SIL Open Font License 1.1. Source: https://github.com/rsms/inter/releases/tag/v4.1. Full license: assets/fonts/OFL.txt.

## SmartLight design assets

The SVG room illustration and icons in assets/design are the original assets used in the SmartLight Figma construction records under design/figma. Scene artwork is rendered with native Flutter shapes.
