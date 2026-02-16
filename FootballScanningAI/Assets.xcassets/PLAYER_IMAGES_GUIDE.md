# Player images – what goes where

Use this as a checklist. Each **imageset name** (left) should contain **one image** (right).

---

## Female – black jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_female_black_jersey` | Face 1, black jersey |
| `player_female_black_jersey_2` | Face 2, black jersey |
| `player_female_black_jersey_3` | Face 3, black jersey |
| `player_female_black_jersey_4` | Face 4, black jersey |

## Female – white jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_female_white_jersey` | Face 1, white jersey |
| `player_female_white_jersey_2` | Face 2, white jersey |
| `player_female_white_jersey_3` | Face 3, white jersey |
| `player_female_white_jersey_4` | Face 4, white jersey |

## Female – blue jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_female_blue_jersey` | Face 1, blue jersey |
| `player_female_blue_jersey_2` | Face 2, blue jersey |
| `player_female_blue_jersey_3` | Face 3, blue jersey |
| `player_female_blue_jersey_4` | Face 4, blue jersey |

## Female – green jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_female_green_jersey` | Face 1, green jersey |
| `player_female_green_jersey_2` | Face 2, green jersey |
| `player_female_green_jersey_3` | Face 3, green jersey |
| `player_female_green_jersey_4` | Face 4, green jersey |

## Female – red jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_female_red_jersey` | Face 1, red jersey |
| `player_female_red_jersey_2` | Face 2, red jersey |
| `player_female_red_jersey_3` | Face 3, red jersey |
| `player_female_red_jersey_4` | Face 4, red jersey |

---

## Male – black jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_male_black_jersey` | Face 1, black jersey |
| `player_male_black_jersey_2` | Face 2, black jersey |
| `player_male_black_jersey_3` | Face 3, black jersey |
| `player_male_black_jersey_4` | Face 4, black jersey |

## Male – white jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_male_white_jersey` | Face 1, white jersey |
| `player_male_white_jersey_2` | Face 2, white jersey |
| `player_male_white_jersey_3` | Face 3, white jersey |
| `player_male_white_jersey_4` | Face 4, white jersey |

## Male – blue jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_male_blue_jersey` | Face 1, blue jersey |
| `player_male_blue_jersey_2` | Face 2, blue jersey |
| `player_male_blue_jersey_3` | Face 3, blue jersey |
| `player_male_blue_jersey_4` | Face 4, blue jersey |

## Male – green jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_male_green_jersey` | Face 1, green jersey |
| `player_male_green_jersey_2` | Face 2, green jersey |
| `player_male_green_jersey_3` | Face 3, green jersey |
| `player_male_green_jersey_4` | Face 4, green jersey |

## Male – red jersey
| Imageset name | Put this in it |
|---------------|-----------------|
| `player_male_red_jersey` | Face 1, red jersey |
| `player_male_red_jersey_2` | Face 2, red jersey |
| `player_male_red_jersey_3` | Face 3, red jersey |
| `player_male_red_jersey_4` | Face 4, red jersey |

---

## How to fix mix-ups in Xcode

1. Open **Assets.xcassets** in Xcode.
2. Click an imageset name in the left list (e.g. `player_female_black_jersey_2`).
3. Check the image in the middle. Use the table above: this set should show **Face 2, black jersey** for that example.
4. If it’s wrong: drag the **correct** image from Finder into the **1x** slot (or onto the imageset name). That replaces the image for that set.
5. Repeat for each imageset until they match the table.

The **name of the imageset** (folder) is what the app uses. The **file name of the image** you drag in doesn’t matter—only that the right picture is in the right imageset.
