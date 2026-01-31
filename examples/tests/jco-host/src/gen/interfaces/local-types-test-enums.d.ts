/** @module Interface local:types-test/enums **/
export function echoColor(c: Color): Color;
export function colorName(c: Color): string;
/**
 * # Variants
 * 
 * ## `"red"`
 * 
 * ## `"green"`
 * 
 * ## `"blue"`
 */
export type Color = 'red' | 'green' | 'blue';
