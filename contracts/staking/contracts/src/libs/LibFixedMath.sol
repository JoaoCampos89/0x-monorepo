/*

  Copyright 2017 Bprotocol Foundation, 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.9;


/// @dev Signed, fixed-point, 127-bit precision math library.
library LibFixedMath {
    int256 private constant FIXED_1 = int256(0x0000000000000000000000000000000080000000000000000000000000000000);

    // 1
    int256 private constant LN_MAX_VAL = FIXED_1;
    // -69.07755278982137043720332303294494434957608235919531845909733017243007692132225692604324818191230406
    int256 private constant EXP_MIN_VAL = int256(0xffffffffffffffffffffffffffffffdd7612c00c0077ada1b83518e8cafc0e90);

    /// @dev Returns the multiplication of two fixed point numbers, reverting on overflow.
    function mul(int256 a, int256 b) internal pure returns (int256 c) {
        c = _mul(a, b) / FIXED_1;
    }

    /// @dev Returns the division of two fixed point numbers.
    function div(int256 a, int256 b) internal pure returns (int256 c) {
        c = _div(_mul(a, FIXED_1), b);
    }

    /// @dev Returns the absolute value of a fixed point number.
    function abs(int256 a) internal pure returns (int256 c) {
        if (a >= 0) {
            c = a;
        } else {
            c = -a;
        }
    }

    /// @dev Convert `n` / 1 to a fixed-point number.
    function toFixed(int256 n) internal pure returns (int256 f) {
        f = _mul(n, FIXED_1);
    }

    /// @dev Convert `n` / `d` to a fixed-point number.
    function toFixed(int256 n, int256 d) internal pure returns (int256 f) {
        f = _div(_mul(n, FIXED_1), d);
    }

    /// @dev Convert a fixed-point number to an integer.
    function toInteger(int256 f) internal pure returns (int256 n) {
        return f >> 127;
    }

    /// @dev Get the natural logarithm of a fixed-point number 0 < `x` <= LN_MAX_VAL
    function ln(int256 x) internal pure returns (int256 r) {
        if (x == FIXED_1) {
            return 0;
        }
        assert(x < LN_MAX_VAL && x > 0);

        int256 y;
        int256 z;
        int256 w;

        // Rewrite the input as a quotient of negative natural exponents and a single residual q, such that 1 < q < 2
        // For example: log(0.3) = log(e^-1 * e^-0.25 * 1.0471028872385522) = 1 - 0.25 - log(1 + 0.0471028872385522)
        // e ^ -64
        if (x <= int256(0x000000000000000000000000000000000000000000000000000000065a751cc8)) {
            r += int256(0xffffffffffffffffffffffffffffffe000000000000000000000000000000000); // - 64
            x = x * FIXED_1 / int256(0x000000000000000000000000000000000000000000000000000000065a751cc8); // / e ^ -64
        }
        // e ^ -32
        if (x <= int256(0x00000000000000000000000000000000000000000001c8464f76164760000000)) {
            r += int256(0xfffffffffffffffffffffffffffffff000000000000000000000000000000000); // - 32
            x = x * FIXED_1 / int256(0x00000000000000000000000000000000000000000001c8464f76164760000000); // / e ^ -32
        }
        // e ^ -16
        if (x <= int256(0x00000000000000000000000000000000000000f1aaddd7742e90000000000000)) {
            r += int256(0xfffffffffffffffffffffffffffffff800000000000000000000000000000000); // - 16
            x = x * FIXED_1 / int256(0x00000000000000000000000000000000000000f1aaddd7742e90000000000000); // / e ^ -16
        }
        // e ^ -8
        if (x <= int256(0x00000000000000000000000000000000000afe10820813d78000000000000000)) {
            r += int256(0xfffffffffffffffffffffffffffffffc00000000000000000000000000000000); // - 8
            x = x * FIXED_1 / int256(0x00000000000000000000000000000000000afe10820813d78000000000000000); // / e ^ -8
        }
        // e ^ -4
        if (x <= int256(0x0000000000000000000000000000000002582ab704279ec00000000000000000)) {
            r += int256(0xfffffffffffffffffffffffffffffffe00000000000000000000000000000000); // - 4
            x = x * FIXED_1 / int256(0x0000000000000000000000000000000002582ab704279ec00000000000000000); // / e ^ -4
        }
        // e ^ -2
        if (x <= int256(0x000000000000000000000000000000001152aaa3bf81cc000000000000000000)) {
            r += int256(0xffffffffffffffffffffffffffffffff00000000000000000000000000000000); // - 2
            x = x * FIXED_1 / int256(0x000000000000000000000000000000001152aaa3bf81cc000000000000000000); // / e ^ -2
        }
        // e ^ -1
        if (x <= int256(0x000000000000000000000000000000002f16ac6c59de70000000000000000000)) {
            r += int256(0xffffffffffffffffffffffffffffffff80000000000000000000000000000000); // - 1
            x = x * FIXED_1 / int256(0x000000000000000000000000000000002f16ac6c59de70000000000000000000); // / e ^ -1
        }
        // e ^ -0.5
        if (x <= int256(0x000000000000000000000000000000004da2cbf1be5828000000000000000000)) {
            r += int256(0xffffffffffffffffffffffffffffffffc0000000000000000000000000000000); // - 0.5
            x = x * FIXED_1 / int256(0x000000000000000000000000000000004da2cbf1be5828000000000000000000); // / e ^ -0.5
        }
        // e ^ -0.25
        if (x <= int256(0x0000000000000000000000000000000063afbe7ab2082c000000000000000000)) {
            r += int256(0xffffffffffffffffffffffffffffffffe0000000000000000000000000000000); // - 0.25
            x = x * FIXED_1 / int256(0x0000000000000000000000000000000063afbe7ab2082c000000000000000000); // / e ^ -0.25
        }
        // `x` is now our residual in the range of 1 <= x <= 2 (or close enough).

        // Add the taylor series for log(1 + z), where z = x - 1
        z = y = x - FIXED_1;
        w = y * y / FIXED_1;
        r += z * (0x100000000000000000000000000000000 - y) / 0x100000000000000000000000000000000; z = z * w / FIXED_1; // add y^01 / 01 - y^02 / 02
        r += z * (0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa - y) / 0x200000000000000000000000000000000; z = z * w / FIXED_1; // add y^03 / 03 - y^04 / 04
        r += z * (0x099999999999999999999999999999999 - y) / 0x300000000000000000000000000000000; z = z * w / FIXED_1; // add y^05 / 05 - y^06 / 06
        r += z * (0x092492492492492492492492492492492 - y) / 0x400000000000000000000000000000000; z = z * w / FIXED_1; // add y^07 / 07 - y^08 / 08
        r += z * (0x08e38e38e38e38e38e38e38e38e38e38e - y) / 0x500000000000000000000000000000000; z = z * w / FIXED_1; // add y^09 / 09 - y^10 / 10
        r += z * (0x08ba2e8ba2e8ba2e8ba2e8ba2e8ba2e8b - y) / 0x600000000000000000000000000000000; z = z * w / FIXED_1; // add y^11 / 11 - y^12 / 12
        r += z * (0x089d89d89d89d89d89d89d89d89d89d89 - y) / 0x700000000000000000000000000000000; z = z * w / FIXED_1; // add y^13 / 13 - y^14 / 14
        r += z * (0x088888888888888888888888888888888 - y) / 0x800000000000000000000000000000000;                      // add y^15 / 15 - y^16 / 16
    }

    /// @dev Compute the natural exponent for a fixed-point number EXP_MIN_VAL <= `x` <= 1
    function exp(int256 x) internal pure returns (int256 r) {
        if (x <= EXP_MIN_VAL) {
            // Saturate to zero below EXP_MIN_VAL.
            return 0;
        }
        if (x == 0) {
            return FIXED_1;
        }
        assert(x < 0);

        // Rewrite the input as a product of positive natural exponents and a
        // single residual q, where q is a number of small magnitude.
        // For example: e^-34.419 = e^(-32 - 2 - 0.419) = e^-32 * e^-2 * e^-0.419
        r = FIXED_1;
        // e ^ 64
        if (x <= -int256(0x0000000000000000000000000000002000000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000002000000000000000000000000000000000); // + 64
            r = r * int256(0x000000000000000000000000000000000000000000000000000000065a751cc8) / FIXED_1; // * e ^ 64
        }
        // e ^ 32
        if (x <= -int256(0x0000000000000000000000000000001000000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000001000000000000000000000000000000000); // + 32
            r = r * int256(0x00000000000000000000000000000000000000000001c8464f76164681e299a0) / FIXED_1; // * e ^ 32
        }
        // e ^ 16
        if (x <= -int256(0x0000000000000000000000000000000800000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000800000000000000000000000000000000); // + 16
            r = r * int256(0x00000000000000000000000000000000000000f1aaddd7742e56d32fb9f99744) / FIXED_1; // * e ^ 16
        }
        // e ^ 8
        if (x <= -int256(0x0000000000000000000000000000000400000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000400000000000000000000000000000000); // + 8
            r = r * int256(0x00000000000000000000000000000000000afe10820813d65dfe6a33c07f738f) / FIXED_1; // * e ^ 8
        }
        // e ^ 4
        if (x <= -int256(0x0000000000000000000000000000000200000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000200000000000000000000000000000000); // + 4
            r = r * int256(0x0000000000000000000000000000000002582ab704279e8efd15e0265855c47a) / FIXED_1; // * e ^ 4
        }
        // e ^ 2
        if (x <= -int256(0x0000000000000000000000000000000100000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000100000000000000000000000000000000); // + 2
            r = r * int256(0x000000000000000000000000000000001152aaa3bf81cb9fdb76eae12d029571) / FIXED_1; // * e ^ 2
        }
        // e ^ 1
        if (x <= -int256(0x0000000000000000000000000000000080000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000080000000000000000000000000000000); // + 1
            r = r * int256(0x000000000000000000000000000000002f16ac6c59de6f8d5d6f63c1482a7c86) / FIXED_1; // * e ^ 1
        }
        // e ^ 0.5
        if (x <= -int256(0x0000000000000000000000000000000040000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000040000000000000000000000000000000); // + 0.5
            r = r * int256(0x000000000000000000000000000000004da2cbf1be5827f9eb3ad1aa9866ebb3) / FIXED_1; // * e ^ 0.5
        }
        // e ^ 0.25
        if (x <= -int256(0x0000000000000000000000000000000020000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000020000000000000000000000000000000); // + 0.25
            r = r * int256(0x0000000000000000000000000000000063afbe7ab2082ba1a0ae5e4eb1b479dc) / FIXED_1; // * e ^ 0.25
        }
        // e ^ 0.125
        if (x <= -int256(0x0000000000000000000000000000000010000000000000000000000000000000)) {
            x += int256(0x0000000000000000000000000000000010000000000000000000000000000000); // + 0.125
            r = r * int256(0x0000000000000000000000000000000070f5a893b608861e1f58934f97aea57d) / FIXED_1; // * e ^ 0.125
        }
        // x is now a small residual close to 0

        // Multiply with the taylor series for e^q
        int256 y;
        int256 z;
        int256 t;
        z = y = x;
        z = z * y / FIXED_1; t += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = z * y / FIXED_1; t += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = z * y / FIXED_1; t += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = z * y / FIXED_1; t += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = z * y / FIXED_1; t += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = z * y / FIXED_1; t += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = z * y / FIXED_1; t += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = z * y / FIXED_1; t += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = z * y / FIXED_1; t += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = z * y / FIXED_1; t += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = z * y / FIXED_1; t += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = z * y / FIXED_1; t += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = z * y / FIXED_1; t += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = z * y / FIXED_1; t += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = z * y / FIXED_1; t += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = z * y / FIXED_1; t += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = z * y / FIXED_1; t += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = z * y / FIXED_1; t += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = z * y / FIXED_1; t += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        t = t / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!
        r = r * t / FIXED_1;
    }

    /// @dev Returns the multiplication two numbers, reverting on overflow.
    function _mul(int256 a, int256 b) private pure returns (int256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        require(c / a == b, "FIXED_MATH_MULTIPLICATION_OVERFLOW");
    }

    /// @dev Returns the division of two numbers, reverting on division by zero.
    function _div(int256 a, int256 b) private pure returns (int256 c) {
        require(b != 0, "FIXED_MATH_DIVISION_BY_ZERO");
        c = a / b;
    }
}